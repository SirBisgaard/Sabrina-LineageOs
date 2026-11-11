// SPDX-License-Identifier: EUPL-1.2
package com.google.android.apps.tv.launcherx;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/** Receives the setup wizard's final launch, completes setup and opens Catapult. */
public class HandoffActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        HomeFixer.completeSetup(this);
        startActivity(new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .setComponent(HomeFixer.CATAPULT_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        finish();
    }
}
