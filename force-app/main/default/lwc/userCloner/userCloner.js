import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getMissingItems from '@salesforce/apex/UserCloneController.getMissingItems';
import processAssignments from '@salesforce/apex/UserCloneController.processAssignments';
import startPermissionCloneJob from '@salesforce/apex/UserCloneController.startPermissionCloneJob';
import getPermissionCloneJobStatus from '@salesforce/apex/UserCloneController.getPermissionCloneJobStatus';
import getSourceUserDefaults from '@salesforce/apex/UserCloneController.getSourceUserDefaults';
import createTargetUser from '@salesforce/apex/UserCloneController.createTargetUser';

export default class UserCloner extends LightningElement {
    @track sourceUserId;
    @track targetUserId;

    @track missingLic = [];
    @track missingPerm = [];
    @track missingMemberships = [];

    @track currentStep = '1';
    @track isProcessing = false;
    @track lastErrors = [];

    @track showCreateUserModal = false;
    @track isCreatingUser = false;

    @track createUserForm = {
        firstName: '',
        lastName: '',
        alias: '',
        email: '',
        username: '',
        communityNickname: '',
        timeZoneSidKey: '',
        localeSidKey: '',
        languageLocaleKey: '',
        emailEncodingKey: '',
        profileId: '',
        roleId: '',
        isActive: true,
        marketingUser: false,
        offlineUser: false,
        knowledgeUser: false,
        flowUser: false,
        serviceCloudUser: false,
        chatUser: false
    };

    @track createUserMeta = {
        userLicenseName: '',
        profileOptions: [],
        roleOptions: [],
        timeZoneOptions: [],
        localeOptions: [],
        languageOptions: [],
        emailEncodingOptions: []
    };

    @track phase2JobId;
    @track phase2JobStatus;
    @track phase2JobItemsProcessed = 0;
    @track phase2JobTotalItems = 0;
    @track phase2JobErrors = 0;
    @track phase2SelectedCount = 0;

    phase2PollTimer;

    disconnectedCallback() {
        this.clearPhase2Polling();
    }

    get isStep1() {
        return this.currentStep === '1';
    }

    get isStep2() {
        return this.currentStep === '2';
    }

    get isStep3() {
        return this.currentStep === '3';
    }

    get hasErrors() {
        return this.lastErrors && this.lastErrors.length > 0;
    }

    get hasLicenses() {
        return this.missingLic && this.missingLic.length > 0;
    }

    get hasPerms() {
        return this.missingPerm && this.missingPerm.length > 0;
    }

    get hasMemberships() {
        return this.missingMemberships && this.missingMemberships.length > 0;
    }

    get step1Variant() {
        return this.currentStep === '1' ? 'brand' : 'neutral';
    }

    get step2Variant() {
        return this.currentStep === '2' ? 'brand' : 'neutral';
    }

    get step3Variant() {
        return this.currentStep === '3' ? 'brand' : 'neutral';
    }

    get totalMissingCount() {
        return this.missingLic.length + this.missingPerm.length + this.missingMemberships.length;
    }

    get analysisSummary() {
        return `Licenses: ${this.missingLic.length} | Permission Assignments: ${this.missingPerm.length} | Groups & Queues: ${this.missingMemberships.length}`;
    }

    get isPhase2JobRunning() {
        return !!this.phase2JobId && !['Completed', 'Failed', 'Aborted'].includes(this.phase2JobStatus);
    }

    get hasPhase2Job() {
        return !!this.phase2JobId;
    }

    get phase2StatusText() {
        if (!this.phase2JobId) {
            return '';
        }
        return `Status: ${this.phase2JobStatus || 'Queued'} | Chunks: ${this.phase2JobItemsProcessed}/${this.phase2JobTotalItems} | Batch Errors: ${this.phase2JobErrors}`;
    }

    get createUserButtonLabel() {
        return this.isCreatingUser ? 'Creating...' : 'Create User';
    }

    handleStepSelect(event) {
        this.currentStep = event.detail.value;
    }

    setStep1() {
        this.currentStep = '1';
    }

    setStep2() {
        this.currentStep = '2';
    }

    setStep3() {
        this.currentStep = '3';
    }

    handleSourceChange(event) {
        this.sourceUserId = event.detail.recordId;
    }

    handleTargetChange(event) {
        this.targetUserId = event.detail.recordId;
    }

    handleAnalyzeClick() {
        this.runCompare('1');
    }

    async runCompare(stepToLandOn) {
        if (!this.sourceUserId || !this.targetUserId) {
            this.showToast('Missing Selection', 'Please select both a source user and a target user.', 'warning');
            return;
        }

        if (this.sourceUserId === this.targetUserId) {
            this.showToast('Invalid Selection', 'Source and target users must be different.', 'error');
            return;
        }

        this.isProcessing = true;

        try {
            const data = await getMissingItems({
                srcId: this.sourceUserId,
                tgtId: this.targetUserId
            });

            this.missingLic = data?.Licenses || [];
            this.missingPerm = data?.PermissionAssignments || [];
            this.missingMemberships = data?.Memberships || [];

            this.currentStep = stepToLandOn || '1';

            if (this.totalMissingCount === 0) {
                this.showToast(
                    'No Gaps Found',
                    'The target user already appears to match the source user for all three phases.',
                    'success'
                );
            }
        } catch (e) {
            this.showToast(
                'Error',
                e?.body?.message || 'Compare failed.',
                'error'
            );
        } finally {
            this.isProcessing = false;
        }
    }

    async cloneLic() {
        const ids = this.getCheckedValues('licCheck');

        this.isProcessing = true;
        this.lastErrors = [];

        try {
            let res = { errorMessages: [], successCount: 0 };

            if (ids.length > 0) {
                res = await processAssignments({
                    tgtId: this.targetUserId,
                    ids,
                    category: 'LIC'
                });
            }

            this.lastErrors = res?.errorMessages || [];
            const successCount = res?.successCount || 0;

            await this.runCompare('2');

            this.showOutcomeToast({
                successCount,
                errorCount: this.lastErrors.length,
                singularLabel: 'license assignment',
                pluralLabel: 'license assignments',
                nothingSelectedMessage: 'No licenses were selected.'
            });
        } catch (e) {
            this.showToast(
                'Error',
                e?.body?.message || 'License cloning failed.',
                'error'
            );
        } finally {
            this.isProcessing = false;
        }
    }

    async clonePerm() {
        const ids = this.getCheckedValues('permCheck');

        if (ids.length === 0) {
            this.showToast('No Selection', 'Select at least one permission assignment.', 'warning');
            return;
        }

        this.isProcessing = true;
        this.lastErrors = [];
        this.phase2SelectedCount = ids.length;

        try {
            const jobId = await startPermissionCloneJob({
                tgtId: this.targetUserId,
                ids
            });

            this.phase2JobId = jobId;
            this.phase2JobStatus = 'Queued';
            this.phase2JobItemsProcessed = 0;
            this.phase2JobTotalItems = 0;
            this.phase2JobErrors = 0;

            this.currentStep = '2';
            this.showToast('Phase 2 Started', `Background permission copy started for ${ids.length} selected assignment(s).`, 'info');

            this.isProcessing = false;
            this.startPhase2Polling();
        } catch (e) {
            this.isProcessing = false;
            this.showToast(
                'Error',
                e?.body?.message || 'Unable to start Phase 2 clone job.',
                'error'
            );
        }
    }

    startPhase2Polling() {
        this.clearPhase2Polling();

        this.phase2PollTimer = window.setInterval(async () => {
            try {
                const status = await getPermissionCloneJobStatus({
                    jobId: this.phase2JobId
                });

                this.phase2JobStatus = status?.status;
                this.phase2JobItemsProcessed = status?.jobItemsProcessed || 0;
                this.phase2JobTotalItems = status?.totalJobItems || 0;
                this.phase2JobErrors = status?.numberOfErrors || 0;

                if (['Completed', 'Failed', 'Aborted'].includes(this.phase2JobStatus)) {
                    this.clearPhase2Polling();

                    if (this.phase2JobStatus === 'Completed') {
                        await this.runCompare('3');

                        if (this.phase2JobErrors > 0) {
                            this.showToast(
                                'Phase 2 Completed with Issues',
                                `Permission copy finished. Salesforce reported ${this.phase2JobErrors} batch error(s).`,
                                'warning'
                            );
                        } else {
                            this.showToast(
                                'Success',
                                'Permission assignments completed.',
                                'success'
                            );
                        }
                    } else {
                        this.showToast(
                            'Error',
                            `Phase 2 job ended with status: ${this.phase2JobStatus}.`,
                            'error'
                        );
                    }
                }
            } catch (e) {
                this.clearPhase2Polling();
                this.showToast(
                    'Error',
                    e?.body?.message || 'Unable to poll Phase 2 job status.',
                    'error'
                );
            }
        }, 2000);
    }

    clearPhase2Polling() {
        if (this.phase2PollTimer) {
            window.clearInterval(this.phase2PollTimer);
            this.phase2PollTimer = null;
        }
    }

    async cloneMemberships() {
        const ids = this.getCheckedValues('memberCheck');

        if (ids.length === 0) {
            this.showToast('No Selection', 'Select at least one group or queue membership.', 'warning');
            return;
        }

        this.isProcessing = true;
        this.lastErrors = [];

        try {
            const res = await processAssignments({
                tgtId: this.targetUserId,
                ids,
                category: 'MEMBER'
            });

            this.lastErrors = res?.errorMessages || [];
            const successCount = res?.successCount || 0;

            await this.runCompare('3');

            this.showOutcomeToast({
                successCount,
                errorCount: this.lastErrors.length,
                singularLabel: 'membership assignment',
                pluralLabel: 'membership assignments',
                nothingSelectedMessage: 'No memberships were selected.'
            });
        } catch (e) {
            this.showToast(
                'Error',
                e?.body?.message || 'Membership cloning failed.',
                'error'
            );
        } finally {
            this.isProcessing = false;
        }
    }

    async openCreateTargetUserModal() {
        if (!this.sourceUserId) {
            this.showToast('Missing Source User', 'Select a source user first.', 'warning');
            return;
        }

        this.isCreatingUser = true;

        try {
            const data = await getSourceUserDefaults({ srcId: this.sourceUserId });

            this.createUserForm = {
                firstName: '',
                lastName: '',
                alias: '',
                email: '',
                username: '',
                communityNickname: '',
                timeZoneSidKey: data.timeZoneSidKey || '',
                localeSidKey: data.localeSidKey || '',
                languageLocaleKey: data.languageLocaleKey || '',
                emailEncodingKey: data.emailEncodingKey || '',
                profileId: data.profileId || '',
                roleId: data.roleId || '',
                isActive: data.isActive === true,
                marketingUser: data.marketingUser === true,
                offlineUser: data.offlineUser === true,
                knowledgeUser: data.knowledgeUser === true,
                flowUser: false,
                serviceCloudUser: data.serviceCloudUser === true,
                chatUser: data.chatUser === true
            };

            this.createUserMeta = {
                userLicenseName: data.userLicenseName || '',
                profileOptions: data.profileOptions || [],
                roleOptions: data.roleOptions || [],
                timeZoneOptions: data.timeZoneOptions || [],
                localeOptions: data.localeOptions || [],
                languageOptions: data.languageOptions || [],
                emailEncodingOptions: data.emailEncodingOptions || []
            };

            this.showCreateUserModal = true;
            console.log('createUserForm before modal', JSON.stringify(this.createUserForm));
        } catch (e) {
            this.showToast('Error', e?.body?.message || 'Unable to load source user defaults.', 'error');
        } finally {
            this.isCreatingUser = false;
        }
    }

    closeCreateUserModal() {
        if (this.isCreatingUser) {
            return;
        }
        this.showCreateUserModal = false;
    }

    handleCreateUserInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;

        this.createUserForm = {
            ...this.createUserForm,
            [field]: value
        };
    }

    handleCreateUserCheckboxChange(event) {
        const field = event.target.dataset.field;

        this.createUserForm = {
            ...this.createUserForm,
            [field]: event.target.checked
        };
    }

    async saveNewTargetUser() {
        if (!this.createUserForm.lastName || !this.createUserForm.lastName.trim()) {
            this.showToast('Missing Last Name', 'Please enter a last name.', 'error');
            return;
        }

        this.isCreatingUser = true;

        try {
            const result = await createTargetUser({
                reqJson: JSON.stringify(this.createUserForm)
            });

            this.targetUserId = result.userId;
            this.showCreateUserModal = false;

            this.showToast('Success', 'Target user created successfully and selected.', 'success');
        } catch (e) {
            this.showToast('Error', e?.body?.message || 'Unable to create target user.', 'error');
        } finally {
            this.isCreatingUser = false;
        }
    }

    handleSelectAllLic(event) {
        this.setAllChecked('licCheck', event.target.checked);
    }

    handleSelectAllPerm(event) {
        this.setAllChecked('permCheck', event.target.checked);
    }

    handleSelectAllMembers(event) {
        this.setAllChecked('memberCheck', event.target.checked);
    }

    getCheckedValues(dataId) {
        return [...this.template.querySelectorAll(`lightning-input[data-id="${dataId}"]`)]
            .filter(cb => cb.checked)
            .map(cb => cb.value);
    }

    setAllChecked(dataId, checked) {
        this.template.querySelectorAll(`lightning-input[data-id="${dataId}"]`)
            .forEach(cb => {
                cb.checked = checked;
            });
    }

    showOutcomeToast({ successCount, errorCount, singularLabel, pluralLabel, nothingSelectedMessage }) {
        if (successCount > 0 && errorCount === 0) {
            const label = successCount === 1 ? singularLabel : pluralLabel;
            this.showToast('Success', `${successCount} ${label} completed.`, 'success');
        } else if (successCount > 0 && errorCount > 0) {
            const label = successCount === 1 ? singularLabel : pluralLabel;
            this.showToast(
                'Partial Success',
                `${successCount} ${label} completed, but some items failed. See Diagnostic Failure Report below.`,
                'warning'
            );
        } else if (successCount === 0 && errorCount > 0) {
            this.showToast(
                'Error',
                'No selected items were completed successfully. See Diagnostic Failure Report below.',
                'error'
            );
        } else {
            this.showToast('No Changes', nothingSelectedMessage, 'info');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}