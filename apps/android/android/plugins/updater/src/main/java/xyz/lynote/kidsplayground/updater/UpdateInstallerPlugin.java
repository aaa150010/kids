package xyz.lynote.kidsplayground.updater;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;

public class UpdateInstallerPlugin extends GodotPlugin {
    public UpdateInstallerPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "UpdateInstaller";
    }

    @UsedByGodot
    public int getVersionCode() {
        Activity appActivity = getActivity();
        if (appActivity == null) return 1;
        try {
            PackageInfo info = appActivity.getPackageManager().getPackageInfo(appActivity.getPackageName(), 0);
            if (Build.VERSION.SDK_INT >= 28) {
                return (int) info.getLongVersionCode();
            }
            return info.versionCode;
        } catch (Exception ignored) {
            return 1;
        }
    }

    @UsedByGodot
    public String getVersionName() {
        Activity appActivity = getActivity();
        if (appActivity == null) return "1.0.0";
        try {
            PackageInfo info = appActivity.getPackageManager().getPackageInfo(appActivity.getPackageName(), 0);
            return info.versionName == null ? "1.0.0" : info.versionName;
        } catch (Exception ignored) {
            return "1.0.0";
        }
    }

    @UsedByGodot
    public boolean canRequestPackageInstalls() {
        Activity appActivity = getActivity();
        if (appActivity == null) return false;
        if (Build.VERSION.SDK_INT < 26) return true;
        return appActivity.getPackageManager().canRequestPackageInstalls();
    }

    @UsedByGodot
    public void openInstallPermissionSettings() {
        Activity appActivity = getActivity();
        if (appActivity == null || Build.VERSION.SDK_INT < 26) return;
        Intent intent = new Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:" + appActivity.getPackageName())
        );
        appActivity.startActivity(intent);
    }

    @UsedByGodot
    public boolean installApk(String path) {
        Activity appActivity = getActivity();
        if (appActivity == null) return false;
        if (!canRequestPackageInstalls()) {
            openInstallPermissionSettings();
            return false;
        }
        File file = new File(path);
        if (!file.exists() || !file.isFile()) return false;
        Uri uri = Uri.parse(
            "content://" + appActivity.getPackageName() + ".update-files/" + file.getName()
        );
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri, "application/vnd.android.package-archive");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        appActivity.startActivity(intent);
        return true;
    }
}
