// SPDX-License-Identifier: EUPL-1.2
package com.google.android.apps.tv.launcherx;

import android.app.role.RoleManager;
import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Process;
import android.provider.Settings;
import android.util.Log;

import java.util.List;

/**
 * Finishes Google TV setup on a build without Google's launcher, and makes Catapult the home app.
 *
 * <p>Google's setup wizard ends by launching {@code com.google.android.apps.tv.launcherx}; this
 * package takes that name so the launch succeeds. Setup is the home app until it finishes, so the
 * wizard's home activity is disabled and the home role is moved to Catapult.
 */
final class HomeFixer {
    static final String TAG = "SabrinaSetupBridge";

    private static final String SETUP_PACKAGE = "com.google.android.tungsten.setupwraith";
    private static final ComponentName SETUP_HOME =
            new ComponentName(SETUP_PACKAGE, SETUP_PACKAGE + ".MainActivity");
    static final String CATAPULT_PACKAGE = "org.lineageos.tv.launcher";
    static final ComponentName CATAPULT_HOME =
            new ComponentName(CATAPULT_PACKAGE, CATAPULT_PACKAGE + ".MainActivity");

    private HomeFixer() {}

    static void completeSetup(Context context) {
        ContentResolver resolver = context.getContentResolver();
        Settings.Secure.putInt(resolver, Settings.Secure.USER_SETUP_COMPLETE, 1);
        Settings.Secure.putInt(resolver, "tv_user_setup_complete", 1);
        Settings.Global.putInt(resolver, Settings.Global.DEVICE_PROVISIONED, 1);
        Log.i(TAG, "setup marked complete");
        promoteCatapult(context);
    }

    static boolean isSetupComplete(Context context) {
        return Settings.Secure.getInt(
                context.getContentResolver(), Settings.Secure.USER_SETUP_COMPLETE, 0) == 1;
    }

    static boolean needsRepair(Context context) {
        PackageManager packages = context.getPackageManager();
        boolean setupHomeEnabled;
        try {
            setupHomeEnabled = packages.getComponentEnabledSetting(SETUP_HOME)
                    != PackageManager.COMPONENT_ENABLED_STATE_DISABLED;
        } catch (IllegalArgumentException e) {
            setupHomeEnabled = false;
        }
        List<String> holders = context.getSystemService(RoleManager.class)
                .getRoleHoldersAsUser(RoleManager.ROLE_HOME, Process.myUserHandle());
        return setupHomeEnabled || !holders.contains(CATAPULT_PACKAGE);
    }

    static void promoteCatapult(Context context) {
        try {
            context.getPackageManager().setComponentEnabledSetting(SETUP_HOME,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP);
            Log.i(TAG, "setup wizard home activity disabled");
        } catch (IllegalArgumentException e) {
            Log.w(TAG, "setup wizard not installed", e);
        }
        context.getSystemService(RoleManager.class).addRoleHolderAsUser(
                RoleManager.ROLE_HOME, CATAPULT_PACKAGE, 0, Process.myUserHandle(),
                context.getMainExecutor(),
                success -> Log.i(TAG, "Catapult home role assigned: " + success));
    }
}
