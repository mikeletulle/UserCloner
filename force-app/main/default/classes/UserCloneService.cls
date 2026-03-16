public class UserCloneService {

    public static void cloneUserPermissions(String inputString) {
        List<String> inputs = inputString.split(',');
        if (inputs.size() < 3) {
            System.debug('Error: Input must be "sourceUser, targetUser, quitOnMissingLicense"');
            return;
        }
        
        String sourceUsername = inputs[0].trim();
        String targetUsername = inputs[1].trim();
        Boolean quitOnMissingLicense = Boolean.valueOf(inputs[2].trim());

        try {
            User sourceUser = [SELECT Id FROM User WHERE Username = :sourceUsername LIMIT 1];
            User targetUser = [SELECT Id FROM User WHERE Username = :targetUsername LIMIT 1];
            
            // 1. Check and Assign Licenses
            if (!validateAndAssignLicenses(sourceUser.Id, targetUser.Id, quitOnMissingLicense)) {
                return; // Exit if quitOnMissingLicense was True and a license was missing
            }

            // 2. Assign Permission Sets (Standard)
            copyPermissionSets(sourceUser.Id, targetUser.Id);

            // 3. Assign Permission Set Groups
            copyPermissionSetGroups(sourceUser.Id, targetUser.Id);

            // 4. Group & Queue Memberships
            copyGroupMemberships(sourceUser.Id, targetUser.Id);

            System.debug('Clone process completed successfully.');

        } catch (Exception e) {
            System.debug('Critical Error in Clone Process: ' + e.getMessage());
        }
    }

    private static Boolean validateAndAssignLicenses(Id srcId, Id tgtId, Boolean quit) {
        // Query licenses assigned to source
        List<PermissionSetLicenseAssign> srcLicenses = [SELECT PermissionSetLicenseId, PermissionSetLicense.MasterLabel 
                                                        FROM PermissionSetLicenseAssign WHERE AssigneeId = :srcId];
        
        // Map of available seats in the Org
        Map<Id, PermissionSetLicense> orgLicenses = new Map<Id, PermissionSetLicense>(
            [SELECT Id, MasterLabel, TotalLicenses, UsedLicenses FROM PermissionSetLicense]
        );

        List<PermissionSetLicenseAssign> toAdd = new List<PermissionSetLicenseAssign>();

        for (PermissionSetLicenseAssign sla : srcLicenses) {
            PermissionSetLicense psl = orgLicenses.get(sla.PermissionSetLicenseId);
            Integer available = psl.TotalLicenses - psl.UsedLicenses;

            if (available <= 0) {
                System.debug('INSUFFICIENT LICENSE: ' + psl.MasterLabel + ' has 0 seats remaining.');
                if (quit) {
                    System.debug('QUIT_ON_MISSING_LICENSE is True. Aborting.');
                    return false; 
                }
                continue; // Skip this one and move to next
            }
            
            toAdd.add(new PermissionSetLicenseAssign(AssigneeId = tgtId, PermissionSetLicenseId = sla.PermissionSetLicenseId));
        }

        if (!toAdd.isEmpty()) {
            Database.insert(toAdd, false);
        }
        return true;
    }

    private static void copyPermissionSets(Id srcId, Id tgtId) {
        // Exclude Profile-owned and PS Group-owned assignments
        List<PermissionSetAssignment> psa = [SELECT PermissionSetId FROM PermissionSetAssignment 
                                             WHERE AssigneeId = :srcId 
                                             AND PermissionSet.IsOwnedByProfile = false 
                                             AND PermissionSetGroupId = null];
        List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
        for (PermissionSetAssignment p : psa) {
            toAdd.add(new PermissionSetAssignment(AssigneeId = tgtId, PermissionSetId = p.PermissionSetId));
        }
        Database.insert(toAdd, false); 
    }

    private static void copyPermissionSetGroups(Id srcId, Id tgtId) {
        List<PermissionSetAssignment> psg = [SELECT PermissionSetGroupId FROM PermissionSetAssignment 
                                             WHERE AssigneeId = :srcId AND PermissionSetGroupId != null];
        List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
        for (PermissionSetAssignment p : psg) {
            toAdd.add(new PermissionSetAssignment(AssigneeId = tgtId, PermissionSetGroupId = p.PermissionSetGroupId));
        }
        Database.insert(toAdd, false);
    }

    private static void copyGroupMemberships(Id srcId, Id tgtId) {
        List<GroupMember> members = [SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :srcId];
        List<GroupMember> toAdd = new List<GroupMember>();
        for (GroupMember gm : members) {
            toAdd.add(new GroupMember(GroupId = gm.GroupId, UserOrGroupId = tgtId));
        }
        Database.insert(toAdd, false);
    }
}