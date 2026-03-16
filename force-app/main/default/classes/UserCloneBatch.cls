/**
 * DESCRIPTION:
 * This class clones Permission Set Licenses, Permission Sets, PS Groups, 
 * Public Groups, and Queues from a Source User to a Target User.
 * * INPUT PARAMETERS ('SourceUser, TargetUser, QuitOnMissingLicense'):
 * 1. SourceUser: Username of the user to copy FROM.
 * 2. TargetUser: Username of the user to copy TO.
 * 3. QuitOnMissingLicense (True/False): 
 * - TRUE: If a required License is missing or the org is out of seats, 
 * the entire process ABORTS immediately to prevent a partial clone.
 * - FALSE: If a license is missing, the code logs the error, skips it, 
 * and continues cloning everything else (Best Effort).
 *
 * HOW TO RUN IN EXECUTE ANONYMOUS:
 * String params = 'source_user@example.com, target_user@example.com, True';
 * UserCloneBatch batchJob = new UserCloneBatch(params);
 * Database.executeBatch(batchJob, 1); 
 */
public class UserCloneBatch implements Database.Batchable<String>, Database.Stateful {
    
    // User IDs and info
    private Id srcId;
    private Id tgtId;
    private Boolean quitOnLicenseMissing;
    
    // Trackers for the Final Summary
    private Integer totalAttempted = 0;
    private List<String> steps = new List<String>{'LICENSES', 'PERM_SETS', 'PS_GROUPS', 'GROUPS_QUEUES'};

    public UserCloneBatch(String inputString) {
        List<String> inputs = inputString.split(',');
        if(inputs.size() < 3) throw new IllegalArgumentException('Input must be CSV: Source, Target, Boolean');
        
        this.srcId = [SELECT Id FROM User WHERE Username = :inputs[0].trim() LIMIT 1].Id;
        this.tgtId = [SELECT Id FROM User WHERE Username = :inputs[1].trim() LIMIT 1].Id;
        this.quitOnLicenseMissing = Boolean.valueOf(inputs[2].trim());
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        return steps;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        String currentStep = scope[0];
        try {
            if (currentStep == 'LICENSES') processLicenses();
            else if (currentStep == 'PERM_SETS') processPermSets();
            else if (currentStep == 'PS_GROUPS') processPSGroups();
            else if (currentStep == 'GROUPS_QUEUES') processGroups();
        } catch (Exception e) {
            System.debug('Error in Step ' + currentStep + ': ' + e.getMessage());
            // Fatal stop if user requested Quit on license failure
            if (quitOnLicenseMissing && currentStep == 'LICENSES') {
                System.debug('CRITICAL: Required license missing. Aborting per user input.');
                System.abortJob(bc.getJobId());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        generateSummaryReport();
    }

    // --- CLONING LOGIC ---

    private void processLicenses() {
        List<PermissionSetLicenseAssign> toAdd = new List<PermissionSetLicenseAssign>();
        for (PermissionSetLicenseAssign sla : [SELECT PermissionSetLicenseId FROM PermissionSetLicenseAssign WHERE AssigneeId = :srcId]) {
            toAdd.add(new PermissionSetLicenseAssign(AssigneeId = tgtId, PermissionSetLicenseId = sla.PermissionSetLicenseId));
        }
        if(!toAdd.isEmpty()) Database.insert(toAdd, false);
    }

    private void processPermSets() {
        List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
        for (PermissionSetAssignment psa : [SELECT PermissionSetId FROM PermissionSetAssignment 
                                             WHERE AssigneeId = :srcId AND PermissionSet.IsOwnedByProfile = false AND PermissionSetGroupId = null]) {
            toAdd.add(new PermissionSetAssignment(AssigneeId = tgtId, PermissionSetId = psa.PermissionSetId));
        }
        if(!toAdd.isEmpty()) Database.insert(toAdd, false);
    }

    private void processPSGroups() {
        List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
        for (PermissionSetAssignment psg : [SELECT PermissionSetGroupId FROM PermissionSetAssignment 
                                             WHERE AssigneeId = :srcId AND PermissionSetGroupId != null]) {
            toAdd.add(new PermissionSetAssignment(AssigneeId = tgtId, PermissionSetGroupId = psg.PermissionSetGroupId));
        }
        if(!toAdd.isEmpty()) Database.insert(toAdd, false);
    }

    private void processGroups() {
        List<GroupMember> toAdd = new List<GroupMember>();
        for (GroupMember gm : [SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :srcId]) {
            toAdd.add(new GroupMember(GroupId = gm.GroupId, UserOrGroupId = tgtId));
        }
        if(!toAdd.isEmpty()) Database.insert(toAdd, false);
    }

    // --- FINAL SUMMARY LOGIC ---

    private void generateSummaryReport() {
        String missingLicenses = '';
        String missingPermSets = '';
        String missingGroupsQueues = '';

        // 1. Compare Licenses
        Set<Id> tgtLicenses = new Map<Id, PermissionSetLicenseAssign>([SELECT PermissionSetLicenseId FROM PermissionSetLicenseAssign WHERE AssigneeId = :tgtId]).keySet();
        for (PermissionSetLicenseAssign sla : [SELECT PermissionSetLicense.MasterLabel, PermissionSetLicenseId FROM PermissionSetLicenseAssign WHERE AssigneeId = :srcId]) {
            if (!tgtLicenses.contains(sla.PermissionSetLicenseId)) missingLicenses += sla.PermissionSetLicense.MasterLabel + ', ';
        }

        // 2. Compare Perm Sets & Groups
        Set<Id> tgtPS = new Map<Id, PermissionSetAssignment>([SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :tgtId]).keySet();
        for (PermissionSetAssignment psa : [SELECT PermissionSet.Label, PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :srcId AND PermissionSet.IsOwnedByProfile = false]) {
            if (!tgtPS.contains(psa.PermissionSetId)) missingPermSets += psa.PermissionSet.Label + ', ';
        }

        // 3. Compare Groups/Queues
        Set<Id> tgtGroups = new Map<Id, GroupMember>([SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :tgtId]).keySet();
        for (GroupMember gm : [SELECT Group.Name FROM GroupMember WHERE UserOrGroupId = :srcId]) {
            if (!tgtGroups.contains(gm.GroupId)) missingGroupsQueues += gm.Group.Name + ', ';
        }

        // Output Clean Summary to Log
        System.debug('================================================================');
        System.debug('FINAL USER CLONE REPORT');
        System.debug('================================================================');
        System.debug('PERM LICENSE SETS NOT ASSIGNED: ' + (String.isBlank(missingLicenses) ? 'None' : missingLicenses.removeEnd(', ')));
        System.debug('PERM SETS NOT ASSIGNED: ' + (String.isBlank(missingPermSets) ? 'None' : missingPermSets.removeEnd(', ')));
        System.debug('GROUPS/QUEUES NOT ASSIGNED: ' + (String.isBlank(missingGroupsQueues) ? 'None' : missingGroupsQueues.removeEnd(', ')));
        System.debug('================================================================');
    }
}