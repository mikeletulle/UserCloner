@isTest
private class UserCloneControllerTest {
    
    @testSetup
    static void setup() {
        // Create a Standard Profile for testing
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        
        // Create a Source User
        User src = new User(
            Alias = 'srcUser', 
            Email = 'src@test.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'Source', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = p.Id, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = 'src' + DateTime.now().getTime() + '@clonertest.com'
        );
        insert src;

        // Create a Target User
        User tgt = new User(
            Alias = 'tgtUser', 
            Email = 'tgt@test.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'Target', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = p.Id, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = 'tgt' + DateTime.now().getTime() + '@clonertest.com'
        );
        insert tgt;
    }

    @isTest
    static void testGetMissingItems() {
        User[] users = [SELECT Id FROM User WHERE LastName IN ('Source', 'Target') ORDER BY LastName DESC];
        Id srcId = users[0].Id;
        Id tgtId = users[1].Id;

        Test.startTest();
        Map<String, List<UserCloneController.MemberWrapper>> results = UserCloneController.getMissingItems(srcId, tgtId);
        Test.stopTest();
        
        Assert.isNotNull(results, 'Results map should be initialized.');
    }

    @isTest
    static void testGetSourceUserDefaults() {
        User src = [SELECT Id FROM User WHERE LastName = 'Source' LIMIT 1];

        Test.startTest();
        UserCloneController.UserCreateDefaults defaults = UserCloneController.getSourceUserDefaults(src.Id);
        Test.stopTest();

        Assert.areEqual(src.Id, defaults.sourceUserId, 'Defaults should match the source user ID.');
    }

    @isTest
    static void testCreateTargetUserAndJobs() {
        User src = [SELECT Id FROM User WHERE LastName = 'Source' LIMIT 1];
        UserCloneController.UserCreateDefaults defaults = UserCloneController.getSourceUserDefaults(src.Id);

        // Build a request object
        UserCloneController.UserCreateRequest req = new UserCloneController.UserCreateRequest();
        req.firstName = 'New';
        req.lastName = 'Cloned';
        req.alias = 'nclon';
        req.email = 'new@test.com';
        req.username = 'newcloned' + DateTime.now().getTime() + '@test.com';
        req.communityNickname = 'nclon';
        req.timeZoneSidKey = defaults.timeZoneSidKey;
        req.localeSidKey = defaults.localeSidKey;
        req.languageLocaleKey = defaults.languageLocaleKey;
        req.emailEncodingKey = defaults.emailEncodingKey;
        req.profileId = defaults.profileId;
        req.isActive = true;

        Test.startTest();
        // Test User Creation
        UserCloneController.UserCreateResult result = UserCloneController.createTargetUser(JSON.serialize(req));
        
        // Test Async Job Trigger
        String jobId = UserCloneController.startPermissionCloneJob(result.userId, new List<String>{src.Id});
        
        // Test Job Status Check
        UserCloneController.JobStatusResult status = UserCloneController.getPermissionCloneJobStatus(jobId);
        Test.stopTest();

        Assert.isNotNull(result.userId, 'New user should have been created.');
        Assert.isNotNull(status.status, 'Job status should be returned.');
    }
}