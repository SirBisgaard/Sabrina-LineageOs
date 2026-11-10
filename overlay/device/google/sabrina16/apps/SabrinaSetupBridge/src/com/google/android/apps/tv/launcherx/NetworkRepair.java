// SPDX-License-Identifier: Apache-2.0
package com.google.android.apps.tv.launcherx;

import android.Manifest;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.NetworkPolicyManager;
import android.util.Log;

import com.android.internal.util.ArrayUtils;

/**
 * Restores network access for installed apps that LineageOS blocked by mistake.
 *
 * <p>LineageOS blocks a newly installed app (POLICY_REJECT_ALL) when it seems to lack the INTERNET
 * permission, but the grant can be missing at install time. Android TV settings have no switch to
 * undo that, so apps that request INTERNET are unblocked here.
 */
final class NetworkRepair {
    private NetworkRepair() {}

    static void unblockAppsRequestingInternet(Context context) {
        NetworkPolicyManager policies = NetworkPolicyManager.from(context);
        for (PackageInfo info : context.getPackageManager().getInstalledPackages(
                PackageManager.GET_PERMISSIONS)) {
            ApplicationInfo app = info.applicationInfo;
            if (app == null || app.isSystemApp()
                    || !ArrayUtils.contains(info.requestedPermissions, Manifest.permission.INTERNET)
                    || (policies.getUidPolicy(app.uid) & NetworkPolicyManager.POLICY_REJECT_ALL) == 0) {
                continue;
            }
            policies.removeUidPolicy(app.uid, NetworkPolicyManager.POLICY_REJECT_ALL);
            Log.i(HomeFixer.TAG, "restored network access for " + info.packageName);
        }
    }
}
