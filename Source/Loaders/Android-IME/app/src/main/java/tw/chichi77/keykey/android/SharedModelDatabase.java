/* Copyright (c) 2026 Chui-Ping Cheng. MIT License. */
package tw.chichi77.keykey.android;

import android.content.Context;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/** One readonly model file for both backends, independently of Java walker setup. */
final class SharedModelDatabase {
    private static final String ASSET_NAME = "KeyKey.db";
    // The shared-model verifier checks this fingerprint so an app upgrade
    // cannot reuse a different model merely because its row count matches.
    static final String INSTALLED_NAME = "KeyKey-smart-ef5288e5a30292d8.db";
    private static final String[] PREVIOUS_INSTALLED_NAMES = {
            "KeyKey-smart-e8e1376cf3a14155.db",
            "KeyKey-smart-5cff8cb097735017.db",
            "KeyKey-smart-16af45d4da0043d3.db",
            "KeyKey-smart-fdd5908af4de6878.db",
            "KeyKey-smart-8bd91213f9fee6d0.db",
            "KeyKey-smart-69975755bc8c9ce2.db",
            "KeyKey-smart-77fb0d9e69871dd6.db",
            "KeyKey-smart-cbe2e10188427976.db",
            "KeyKey-smart-b212cb38bd3281a7.db",
            "KeyKey-smart-8fc3aead36cefd16.db",
            "KeyKey-smart-1ffa53b37c8293b7.db",
            "KeyKey-smart-ce6c2b1248351223.db",
            "KeyKey-smart-573f733b2affa857.db",
            "KeyKey-smart-939baee5d956363f.db",
            "KeyKey-smart-e8f034598d2e153e.db",
            "KeyKey-smart-8f1cb45f51fb2c27.db",
            "KeyKey-smart-28b18de318ac13ee.db",
            "KeyKey-smart-885614.db",
            "KeyKey-smart-1.2.10.db",
            "KeyKey-smart-reading-v2.db",
            "KeyKey-smart-reading-v3.db",
    };

    private static final String EXPECTED_SHA256 =
            "ef5288e5a30292d86d5b608f59e636a06697e5535dd82c7d97f058e8cc6d7a77";
    private static File verifiedFile;
    private static long verifiedLength;
    private static long verifiedModified;

    private SharedModelDatabase() {}

    static File location(Context context) {
        return new File(context.getNoBackupFilesDir(), INSTALLED_NAME);
    }

    static synchronized File install(Context context) throws IOException {
        File destination = location(context);
        if (destination.equals(verifiedFile) && destination.isFile()
                && destination.length() == verifiedLength
                && destination.lastModified() == verifiedModified) return destination;
        if (!destination.isFile() || !EXPECTED_SHA256.equals(digest(destination))) {
            File directory = destination.getParentFile();
            if (!directory.isDirectory() && !directory.mkdirs()) {
                throw new IOException("Unable to create the shared model directory");
            }
            File temporary = File.createTempFile(INSTALLED_NAME + ".", ".tmp", directory);
            try {
                try (InputStream input = context.getAssets().open(ASSET_NAME);
                     FileOutputStream output = new FileOutputStream(temporary)) {
                    byte[] buffer = new byte[64 * 1024];
                    int count;
                    while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                    output.getFD().sync();
                }
                if (!EXPECTED_SHA256.equals(digest(temporary))) {
                    throw new IOException("Bundled KeyKey.db does not match its shared model hash");
                }
                if (!temporary.renameTo(destination)) throw new IOException("Unable to install " + ASSET_NAME);
            } finally {
                if (temporary.exists()) temporary.delete();
            }
        }
        verifiedFile = destination;
        verifiedLength = destination.length();
        verifiedModified = destination.lastModified();
        for (String previousName : PREVIOUS_INSTALLED_NAMES) {
            new File(destination.getParentFile(), previousName).delete();
        }
        return destination;
    }

    private static String digest(File file) throws IOException {
        final MessageDigest digest;
        try { digest = MessageDigest.getInstance("SHA-256"); }
        catch (NoSuchAlgorithmException error) { throw new IOException("SHA-256 is unavailable", error); }
        try (InputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        StringBuilder result = new StringBuilder(64);
        for (byte value : digest.digest()) result.append(String.format(java.util.Locale.ROOT, "%02x", value & 0xff));
        return result.toString();
    }
}
