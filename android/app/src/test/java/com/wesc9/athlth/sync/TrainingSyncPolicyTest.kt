package com.wesc9.athlth.sync

import org.junit.Assert.assertEquals
import org.junit.Test

class TrainingSyncPolicyTest {
    @Test fun deniedConsentNeverUploads() {
        assertEquals(SyncDecision.BLOCKED, TrainingSyncPolicy.decide(false,
            LocalPlan("p","{}",null,true), null))
    }

    @Test fun twoOfflineEditsNeverSilentlyOverwrite() {
        assertEquals(SyncDecision.CONFLICT, TrainingSyncPolicy.decide(true,
            LocalPlan("p","local",4,true), RemotePlan("p","remote",5,1,false)))
    }

    @Test fun cleanLocalCopyReceivesCloudEdit() {
        assertEquals(SyncDecision.DOWNLOAD, TrainingSyncPolicy.decide(true,
            LocalPlan("p","old",4,false), RemotePlan("p","new",5,1,false)))
    }

    @Test fun matchingRevisionAllowsUpload() {
        assertEquals(SyncDecision.UPLOAD, TrainingSyncPolicy.decide(true,
            LocalPlan("p","local",4,true), RemotePlan("p","remote",4,1,false)))
    }

    @Test fun manualLocalChangesConflictWithRemoteDeletion() {
        assertEquals(SyncDecision.CONFLICT, TrainingSyncPolicy.decide(true,
            LocalPlan("p","local",4,true), RemotePlan("p","old",5,1,true)))
    }
}
