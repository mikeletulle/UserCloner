public with sharing class UserCloneController {

    public class MemberWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String type; // LIC, PSG, PS, GRP, QUEUE
        @AuraEnabled public String icon;
    }

    public class ProcessResult {
        @AuraEnabled public List<String> errorMessages = new List<String>();
        @AuraEnabled public Integer successCount = 0;
    }

    public class SelectOptionWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public SelectOptionWrapper() {}

        public SelectOptionWrapper(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class UserCreateDefaults {
        @AuraEnabled public String sourceUserId;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String alias;
        @AuraEnabled public String email;
        @AuraEnabled public String username;
        @AuraEnabled public String communityNickname;
        @AuraEnabled public String timeZoneSidKey;
        @AuraEnabled public String localeSidKey;
        @AuraEnabled public String languageLocaleKey;
        @AuraEnabled public String emailEncodingKey;
        @AuraEnabled public String profileId;
        @AuraEnabled public String roleId;
        @AuraEnabled public String profileName;
        @AuraEnabled public String roleName;
        @AuraEnabled public String userLicenseName;

        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean marketingUser;
        @AuraEnabled public Boolean offlineUser;
        @AuraEnabled public Boolean knowledgeUser;
        @AuraEnabled public Boolean serviceCloudUser;
        @AuraEnabled public Boolean chatUser;

        @AuraEnabled public List<SelectOptionWrapper> profileOptions = new List<SelectOptionWrapper>();
        @AuraEnabled public List<SelectOptionWrapper> roleOptions = new List<SelectOptionWrapper>();
        @AuraEnabled public List<SelectOptionWrapper> timeZoneOptions = new List<SelectOptionWrapper>();
        @AuraEnabled public List<SelectOptionWrapper> localeOptions = new List<SelectOptionWrapper>();
        @AuraEnabled public List<SelectOptionWrapper> languageOptions = new List<SelectOptionWrapper>();
        @AuraEnabled public List<SelectOptionWrapper> emailEncodingOptions = new List<SelectOptionWrapper>();
    }

    public class UserCreateRequest {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String alias;
        @AuraEnabled public String email;
        @AuraEnabled public String username;
        @AuraEnabled public String communityNickname;
        @AuraEnabled public String timeZoneSidKey;
        @AuraEnabled public String localeSidKey;
        @AuraEnabled public String languageLocaleKey;
        @AuraEnabled public String emailEncodingKey;
        @AuraEnabled public String profileId;
        @AuraEnabled public String roleId;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean marketingUser;
        @AuraEnabled public Boolean offlineUser;
        @AuraEnabled public Boolean knowledgeUser;
        @AuraEnabled public Boolean flowUser;
        @AuraEnabled public Boolean serviceCloudUser;
        @AuraEnabled public Boolean chatUser;
    }

    public class UserCreateResult {
        @AuraEnabled public String userId;
        @AuraEnabled public String userName;
    }

    public class JobStatusResult {
        @AuraEnabled public String jobId;
        @AuraEnabled public String status;
        @AuraEnabled public Integer jobItemsProcessed;
        @AuraEnabled public Integer totalJobItems;
        @AuraEnabled public Integer numberOfErrors;
        @AuraEnabled public String extendedStatus;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, List<MemberWrapper>> getMissingItems(Id srcId, Id tgtId) {
        Map<String, List<MemberWrapper>> results = new Map<String, List<MemberWrapper>>{
            'Licenses' => new List<MemberWrapper>(),
            'PermissionAssignments' => new List<MemberWrapper>(),
            'Memberships' => new List<MemberWrapper>()
        };

        if (srcId == null || tgtId == null || srcId == tgtId) {
            return results;
        }

        // =========================
        // PHASE 1: LICENSES
        // =========================
        Set<Id> tgtLicIds = new Set<Id>();
        for (PermissionSetLicenseAssign sla : [
            SELECT PermissionSetLicenseId
            FROM PermissionSetLicenseAssign
            WHERE AssigneeId = :tgtId
        ]) {
            tgtLicIds.add(sla.PermissionSetLicenseId);
        }

        for (PermissionSetLicenseAssign srcLic : [
            SELECT PermissionSetLicenseId, PermissionSetLicense.MasterLabel
            FROM PermissionSetLicenseAssign
            WHERE AssigneeId = :srcId
        ]) {
            if (!tgtLicIds.contains(srcLic.PermissionSetLicenseId)) {
                results.get('Licenses').add(
                    createWrapper(
                        srcLic.PermissionSetLicenseId,
                        srcLic.PermissionSetLicense.MasterLabel,
                        'LIC',
                        'utility:key'
                    )
                );
            }
        }

        // =========================
        // PHASE 2A: PERMISSION SET GROUPS
        // =========================
        Set<Id> tgtPSGIds = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT PermissionSetGroupId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :tgtId
            AND PermissionSetGroupId != null
        ]) {
            tgtPSGIds.add(psa.PermissionSetGroupId);
        }

        for (PermissionSetAssignment srcPsg : [
            SELECT PermissionSetGroupId, PermissionSetGroup.DeveloperName
            FROM PermissionSetAssignment
            WHERE AssigneeId = :srcId
            AND PermissionSetGroupId != null
        ]) {
            if (!tgtPSGIds.contains(srcPsg.PermissionSetGroupId)) {
                results.get('PermissionAssignments').add(
                    createWrapper(
                        srcPsg.PermissionSetGroupId,
                        srcPsg.PermissionSetGroup.DeveloperName + ' (Group)',
                        'PSG',
                        'utility:layers'
                    )
                );
            }
        }

        // =========================
        // PHASE 2B: INDIVIDUAL PERMISSION SETS
        // Exclude any PS already granted by target PSGs
        // =========================
        Set<Id> tgtDirectPSIds = new Set<Id>();
        Set<Id> tgtPSGIdsForComponents = new Set<Id>();
        Set<Id> tgtPSIdsViaGroup = new Set<Id>();

        for (PermissionSetAssignment psa : [
            SELECT PermissionSetId, PermissionSetGroupId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :tgtId
        ]) {
            if (psa.PermissionSetId != null) {
                tgtDirectPSIds.add(psa.PermissionSetId);
            }
            if (psa.PermissionSetGroupId != null) {
                tgtPSGIdsForComponents.add(psa.PermissionSetGroupId);
            }
        }

        if (!tgtPSGIdsForComponents.isEmpty()) {
            for (PermissionSetGroupComponent comp : [
                SELECT PermissionSetId
                FROM PermissionSetGroupComponent
                WHERE PermissionSetGroupId IN :tgtPSGIdsForComponents
            ]) {
                tgtPSIdsViaGroup.add(comp.PermissionSetId);
            }
        }

        for (PermissionSetAssignment srcPs : [
            SELECT PermissionSetId, PermissionSet.Label, PermissionSet.IsOwnedByProfile
            FROM PermissionSetAssignment
            WHERE AssigneeId = :srcId
            AND PermissionSetId != null
            AND PermissionSetGroupId = null
            AND PermissionSet.IsOwnedByProfile = false
        ]) {
            Boolean alreadyDirect = tgtDirectPSIds.contains(srcPs.PermissionSetId);
            Boolean alreadyViaGroup = tgtPSIdsViaGroup.contains(srcPs.PermissionSetId);

            if (!alreadyDirect && !alreadyViaGroup) {
                results.get('PermissionAssignments').add(
                    createWrapper(
                        srcPs.PermissionSetId,
                        srcPs.PermissionSet.Label,
                        'PS',
                        'utility:lock'
                    )
                );
            }
        }

        // =========================
        // PHASE 3: GROUPS & QUEUES
        // =========================
        Set<Id> tgtGroupIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId
            FROM GroupMember
            WHERE UserOrGroupId = :tgtId
        ]) {
            tgtGroupIds.add(gm.GroupId);
        }

        for (GroupMember srcGm : [
            SELECT GroupId, Group.Name, Group.Type
            FROM GroupMember
            WHERE UserOrGroupId = :srcId
            AND Group.Type IN ('Regular', 'Queue')
        ]) {
            if (!tgtGroupIds.contains(srcGm.GroupId)) {
                String typeLabel = srcGm.Group.Type == 'Queue' ? 'QUEUE' : 'GRP';
                String iconName = srcGm.Group.Type == 'Queue' ? 'utility:multi_select_list' : 'utility:groups';

                results.get('Memberships').add(
                    createWrapper(
                        srcGm.GroupId,
                        srcGm.Group.Name + ' (' + srcGm.Group.Type + ')',
                        typeLabel,
                        iconName
                    )
                );
            }
        }

        return results;
    }

    @AuraEnabled
    public static ProcessResult processAssignments(Id tgtId, List<String> ids, String category) {
        if (category == 'PERM') {
            throw new AuraHandledException('Phase 2 now runs asynchronously. Use startPermissionCloneJob instead.');
        }

        Set<Id> idSet = toIdSet(ids);
        return processAssignmentsSync(tgtId, idSet, category);
    }

    @AuraEnabled
    public static String startPermissionCloneJob(Id tgtId, List<String> ids) {
        if (tgtId == null) {
            throw new AuraHandledException('Target user is required.');
        }

        Set<Id> idSet = toIdSet(ids);
        if (idSet.isEmpty()) {
            throw new AuraHandledException('At least one permission assignment must be selected.');
        }

        PermissionCloneBatch batchJob = new PermissionCloneBatch(tgtId, new List<Id>(idSet));
        return Database.executeBatch(batchJob, 25);
    }

    @AuraEnabled(cacheable=false)
    public static JobStatusResult getPermissionCloneJobStatus(String jobId) {
        if (String.isBlank(jobId)) {
            throw new AuraHandledException('Job Id is required.');
        }

        AsyncApexJob job = [
            SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, ExtendedStatus
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        JobStatusResult result = new JobStatusResult();
        result.jobId = job.Id;
        result.status = job.Status;
        result.jobItemsProcessed = job.JobItemsProcessed;
        result.totalJobItems = job.TotalJobItems;
        result.numberOfErrors = job.NumberOfErrors;
        result.extendedStatus = job.ExtendedStatus;
        return result;
    }

    private static ProcessResult processAssignmentsSync(Id tgtId, Set<Id> idSet, String category) {
        ProcessResult res = new ProcessResult();

        if (tgtId == null || idSet == null || idSet.isEmpty() || String.isBlank(category)) {
            return res;
        }

        List<SObject> toInsert = new List<SObject>();
        Map<Id, String> labelMap = new Map<Id, String>();

        if (category == 'LIC') {
            for (PermissionSetLicense psl : [
                SELECT Id, MasterLabel
                FROM PermissionSetLicense
                WHERE Id IN :idSet
            ]) {
                toInsert.add(new PermissionSetLicenseAssign(
                    AssigneeId = tgtId,
                    PermissionSetLicenseId = psl.Id
                ));
                labelMap.put(psl.Id, psl.MasterLabel);
            }

        } else if (category == 'MEMBER') {
            for (Group g : [
                SELECT Id, Name
                FROM Group
                WHERE Id IN :idSet
                AND Type IN ('Regular', 'Queue')
            ]) {
                toInsert.add(new GroupMember(
                    UserOrGroupId = tgtId,
                    GroupId = g.Id
                ));
                labelMap.put(g.Id, g.Name);
            }
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] srList = Database.insert(toInsert, false);

            for (Integer i = 0; i < srList.size(); i++) {
                if (srList[i].isSuccess()) {
                    res.successCount++;
                } else {
                    String msg = srList[i].getErrors()[0].getMessage();
                    if (!msg.contains('Duplicate')) {
                        SObject obj = toInsert[i];
                        Id errId;

                        if (obj.getSObjectType() == GroupMember.SObjectType) {
                            errId = (Id)obj.get('GroupId');
                        } else {
                            errId = (Id)obj.get('PermissionSetLicenseId');
                        }

                        String label = labelMap.containsKey(errId) ? labelMap.get(errId) : 'Unknown Item';
                        res.errorMessages.add(label + ': ' + msg);
                    }
                }
            }
        }

        return res;
    }



    @AuraEnabled(cacheable=false)
    public static UserCreateDefaults getSourceUserDefaults(Id srcId) {
        if (srcId == null) {
            throw new AuraHandledException('A source user is required.');
        }

        User src = [
            SELECT Id, FirstName, LastName, Alias, Email, Username, CommunityNickname,
                   TimeZoneSidKey, LocaleSidKey, LanguageLocaleKey, EmailEncodingKey,
                   ProfileId, Profile.Name, UserRoleId, UserRole.Name,
                   IsActive, UserPermissionsMarketingUser, UserPermissionsOfflineUser,
                   UserPermissionsKnowledgeUser, UserPermissionsInteractionUser,
                   UserPermissionsSupportUser
            FROM User
            WHERE Id = :srcId
            LIMIT 1
        ];

        UserCreateDefaults d = new UserCreateDefaults();
        d.sourceUserId = src.Id;
        d.firstName = src.FirstName;
        d.lastName = src.LastName;
        d.alias = src.Alias;
        d.email = src.Email;
        d.username = '';
        d.communityNickname = src.CommunityNickname;
        d.timeZoneSidKey = src.TimeZoneSidKey;
        d.localeSidKey = src.LocaleSidKey;
        d.languageLocaleKey = src.LanguageLocaleKey;
        d.emailEncodingKey = src.EmailEncodingKey;
        d.profileId = src.ProfileId;
        d.roleId = src.UserRoleId;
        d.profileName = src.Profile != null ? src.Profile.Name : null;
        d.roleName = src.UserRole != null ? src.UserRole.Name : null;

        d.isActive = src.IsActive;
        d.marketingUser = src.UserPermissionsMarketingUser;
        d.offlineUser = src.UserPermissionsOfflineUser;
        d.knowledgeUser = src.UserPermissionsKnowledgeUser;
        d.chatUser = src.UserPermissionsInteractionUser;
        d.serviceCloudUser = src.UserPermissionsSupportUser;

        Profile p = [
            SELECT Id, Name, UserLicense.Name
            FROM Profile
            WHERE Id = :src.ProfileId
            LIMIT 1
        ];
        d.userLicenseName = p.UserLicense != null ? p.UserLicense.Name : null;

        for (Profile prof : [
            SELECT Id, Name
            FROM Profile
            ORDER BY Name
        ]) {
            d.profileOptions.add(new SelectOptionWrapper(prof.Name, prof.Id));
        }

        d.roleOptions.add(new SelectOptionWrapper('-- None --', ''));
        for (UserRole role : [
            SELECT Id, Name
            FROM UserRole
            ORDER BY Name
        ]) {
            d.roleOptions.add(new SelectOptionWrapper(role.Name, role.Id));
        }

        for (Schema.PicklistEntry pe : User.TimeZoneSidKey.getDescribe().getPicklistValues()) {
            d.timeZoneOptions.add(new SelectOptionWrapper(pe.getLabel(), pe.getValue()));
        }

        for (Schema.PicklistEntry pe : User.LocaleSidKey.getDescribe().getPicklistValues()) {
            d.localeOptions.add(new SelectOptionWrapper(pe.getLabel(), pe.getValue()));
        }

        for (Schema.PicklistEntry pe : User.LanguageLocaleKey.getDescribe().getPicklistValues()) {
            d.languageOptions.add(new SelectOptionWrapper(pe.getLabel(), pe.getValue()));
        }

        for (Schema.PicklistEntry pe : User.EmailEncodingKey.getDescribe().getPicklistValues()) {
            d.emailEncodingOptions.add(new SelectOptionWrapper(pe.getLabel(), pe.getValue()));
        }

        return d;
    }

    @AuraEnabled
    public static UserCreateResult createTargetUser(String reqJson) {
        if (String.isBlank(reqJson)) {
            throw new AuraHandledException('User request was not provided.');
        }

        UserCreateRequest req = (UserCreateRequest) JSON.deserialize(reqJson, UserCreateRequest.class);

        if (req == null) {
            throw new AuraHandledException('User request was not provided.');
        }
        if (String.isBlank(req.lastName)) {
            throw new AuraHandledException('Last Name is required.');
        }
        if (String.isBlank(req.alias)) {
            throw new AuraHandledException('Alias is required.');
        }
        if (String.isBlank(req.email)) {
            throw new AuraHandledException('Email is required.');
        }
        if (String.isBlank(req.username)) {
            throw new AuraHandledException('Username is required.');
        }
        if (String.isBlank(req.communityNickname)) {
            throw new AuraHandledException('Nickname is required.');
        }
        if (String.isBlank(req.timeZoneSidKey)) {
            throw new AuraHandledException('Time Zone is required.');
        }
        if (String.isBlank(req.localeSidKey)) {
            throw new AuraHandledException('Locale is required.');
        }
        if (String.isBlank(req.languageLocaleKey)) {
            throw new AuraHandledException('Language is required.');
        }
        if (String.isBlank(req.emailEncodingKey)) {
            throw new AuraHandledException('Email Encoding is required.');
        }
        if (String.isBlank(req.profileId)) {
            throw new AuraHandledException('Profile is required.');
        }

        User u = new User();
        u.FirstName = req.firstName;
        u.LastName = req.lastName;
        u.Alias = req.alias.length() > 8 ? req.alias.substring(0, 8) : req.alias;
        u.Email = req.email;
        u.Username = req.username;
        u.CommunityNickname = req.communityNickname;
        u.TimeZoneSidKey = req.timeZoneSidKey;
        u.LocaleSidKey = req.localeSidKey;
        u.LanguageLocaleKey = req.languageLocaleKey;
        u.EmailEncodingKey = req.emailEncodingKey;
        u.ProfileId = req.profileId;
        u.UserRoleId = String.isBlank(req.roleId) ? null : req.roleId;

        if (req.isActive != null) {
            u.IsActive = req.isActive;
        }

        u.UserPermissionsMarketingUser = req.marketingUser == true;
        u.UserPermissionsOfflineUser = req.offlineUser == true;
        u.UserPermissionsKnowledgeUser = req.knowledgeUser == true;
        u.UserPermissionsInteractionUser = req.chatUser == true;
        u.UserPermissionsSupportUser = req.serviceCloudUser == true;

        insert u;

        UserCreateResult result = new UserCreateResult();
        result.userId = u.Id;
        result.userName = (u.FirstName != null ? u.FirstName + ' ' : '') + u.LastName;
        return result;
    }

    private static Set<Id> toIdSet(List<String> ids) {
        Set<Id> idSet = new Set<Id>();
        if (ids == null) {
            return idSet;
        }

        for (String s : ids) {
            if (!String.isBlank(s)) {
                idSet.add((Id)s);
            }
        }
        return idSet;
    }

    private static MemberWrapper createWrapper(Id id, String label, String type, String icon) {
        MemberWrapper w = new MemberWrapper();
        w.id = String.valueOf(id);
        w.label = label;
        w.type = type;
        w.icon = icon;
        return w;
    }
}