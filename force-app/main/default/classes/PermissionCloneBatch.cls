public with sharing class PermissionCloneBatch implements Database.Batchable<Id>, Database.Stateful {
    private Id targetUserId;
    private List<Id> selectedIds;
    private Set<Id> allSelectedPSGIds = new Set<Id>();

    public PermissionCloneBatch(Id tgtId, List<Id> ids) {
        targetUserId = tgtId;
        selectedIds = ids == null ? new List<Id>() : ids;

        if (!selectedIds.isEmpty()) {
            for (PermissionSetGroup psg : [
                SELECT Id
                FROM PermissionSetGroup
                WHERE Id IN :selectedIds
            ]) {
                allSelectedPSGIds.add(psg.Id);
            }
        }
    }

    public Iterable<Id> start(Database.BatchableContext bc) {
        return selectedIds;
    }

    public void execute(Database.BatchableContext bc, List<Id> scopeIds) {
        if (scopeIds == null || scopeIds.isEmpty()) {
            return;
        }

        List<SObject> toInsert = new List<SObject>();

        // Add PSG assignments in this scope
        Set<Id> scopePSGIds = new Set<Id>();
        for (PermissionSetGroup psg : [
            SELECT Id, DeveloperName
            FROM PermissionSetGroup
            WHERE Id IN :scopeIds
        ]) {
            scopePSGIds.add(psg.Id);
            toInsert.add(new PermissionSetAssignment(
                AssigneeId = targetUserId,
                PermissionSetGroupId = psg.Id
            ));
        }

        // Existing target PSGs
        Set<Id> tgtAssignedPSGIds = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT PermissionSetGroupId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :targetUserId
            AND PermissionSetGroupId != null
        ]) {
            tgtAssignedPSGIds.add(psa.PermissionSetGroupId);
        }

        // Effective PSGs = existing + any PSG selected in the entire job
        Set<Id> effectivePSGIds = new Set<Id>();
        effectivePSGIds.addAll(tgtAssignedPSGIds);
        effectivePSGIds.addAll(allSelectedPSGIds);

        Set<Id> psIdsCoveredByGroups = new Set<Id>();
        if (!effectivePSGIds.isEmpty()) {
            for (PermissionSetGroupComponent comp : [
                SELECT PermissionSetId
                FROM PermissionSetGroupComponent
                WHERE PermissionSetGroupId IN :effectivePSGIds
            ]) {
                psIdsCoveredByGroups.add(comp.PermissionSetId);
            }
        }

        // Add direct Permission Sets in this scope, unless covered by a PSG
        for (PermissionSet ps : [
            SELECT Id, Label
            FROM PermissionSet
            WHERE Id IN :scopeIds
            AND Id NOT IN :scopePSGIds
        ]) {
            if (psIdsCoveredByGroups.contains(ps.Id)) {
                continue;
            }

            toInsert.add(new PermissionSetAssignment(
                AssigneeId = targetUserId,
                PermissionSetId = ps.Id
            ));
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        // No-op for now.
    }
}