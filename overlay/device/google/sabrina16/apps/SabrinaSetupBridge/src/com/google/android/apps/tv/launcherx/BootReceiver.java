// SPDX-License-Identifier: EUPL-1.2
package com.google.android.apps.tv.launcherx;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;
import android.util.Log;

/**
 * After boot, blocks automatic OTA updates, unblocks wrongly blocked apps and restores Catapult
 * as home if needed.
 */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            return;
        }
        Settings.Global.putInt(context.getContentResolver(), "ota_disable_automatic_update", 1);
        NetworkRepair.unblockAppsRequestingInternet(context);
        if (!HomeFixer.isSetupComplete(context) || !HomeFixer.needsRepair(context)) {
            return;
        }
        Log.i(HomeFixer.TAG, "repairing home app after boot");
        HomeFixer.promoteCatapult(context);
    }
}
