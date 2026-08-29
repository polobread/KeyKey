package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;

import java.util.concurrent.TimeUnit;

final class SupporterState {
    static final long TRIAL_DURATION_MILLIS = TimeUnit.DAYS.toMillis(30);
    static final String PREFERENCES_NAME = "supporter_state";
    static final String KEY_SUPPORTER = "is_supporter";
    private static volatile long cachedFirstInstallTime = -1L;

    private SupporterState() {}

    static boolean isTrialExpired(Context context) {
        return isTrialExpired(firstInstallTime(context), System.currentTimeMillis());
    }

    static boolean isSupporter(Context context) {
        return preferences(context).getBoolean(KEY_SUPPORTER, false);
    }

    static boolean shouldShowSupportPrompt(Context context) {
        return shouldShowSupportPrompt(
                firstInstallTime(context), System.currentTimeMillis(), isSupporter(context));
    }

    static boolean isTrialExpired(long installTimeMillis, long nowMillis) {
        return nowMillis - installTimeMillis >= TRIAL_DURATION_MILLIS;
    }

    static boolean shouldShowSupportPrompt(long installTimeMillis, long nowMillis,
                                           boolean supporter) {
        return !supporter && isTrialExpired(installTimeMillis, nowMillis);
    }

    static void setSupporter(Context context, boolean supporter) {
        preferences(context).edit().putBoolean(KEY_SUPPORTER, supporter).apply();
    }

    static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
    }

    private static long firstInstallTime(Context context) {
        long cached = cachedFirstInstallTime;
        if (cached >= 0L) return cached;
        try {
            PackageInfo info = context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), 0);
            cachedFirstInstallTime = info.firstInstallTime;
            return info.firstInstallTime;
        } catch (PackageManager.NameNotFoundException error) {
            return System.currentTimeMillis();
        }
    }
}
