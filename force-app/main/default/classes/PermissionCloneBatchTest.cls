@isTest
private class PermissionCloneBatchTest {
    @isTest
    static void testPermissionBatchExecution() {
        // 1. Setup: Create a Target User
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User tgtUser = new User(
            Alias = 'tgtClon',
            Email = 'testclone@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + DateTime.now().getTime() + '@clonertest.com'
        );
        insert tgtUser;

        // 2. Setup: Find an existing Permission Set (Standard or Custom) to use as a dummy ID
        // We exclude Profile-owned ones as the batch logic filters those out
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE IsOwnedByProfile = false LIMIT 1];
        
        // 3. Optional: Try to find a Permission Set Group if one exists in the org
        List<PermissionSetGroup> psgList = [SELECT Id FROM PermissionSetGroup LIMIT 1];
        List<Id> idsToClone = new List<Id>{ps.Id};
        if(!psgList.isEmpty()) {
            idsToClone.add(psgList[0].Id);
        }

        // 4. Execute the Batch
        Test.startTest();
        PermissionCloneBatch batchJob = new PermissionCloneBatch(tgtUser.Id, idsToClone);
        Database.executeBatch(batchJob);
        Test.stopTest();

        // 5. Verification: Check if assignments were created
        List<PermissionSetAssignment> results = [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :tgtUser.Id];
        Assert.isTrue(results.size() > 0, 'At least one assignment should have been created for the target user.');
    }

    @isTest
    static void testEmptyScope() {
        // Test how the batch handles a null or empty list of IDs
        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        Test.startTest();
        PermissionCloneBatch emptyBatch = new PermissionCloneBatch(u.Id, null);
        Database.executeBatch(emptyBatch);
        Test.stopTest();
        
        // No assertions needed for coverage, just ensuring no exceptions are thrown
    }
}