package tw.chichi77.keykey.android;

import android.content.res.AssetManager;
import android.util.Log;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

/** Converts committed Han characters using the desktop OpenVanilla table. */
final class SimplifiedChineseOutput {
    private final Map<Character, Character> mappings;

    private SimplifiedChineseOutput(Map<Character, Character> mappings) {
        this.mappings = mappings;
    }

    static SimplifiedChineseOutput load(AssetManager assets) {
        try (var reader = new BufferedReader(new InputStreamReader(
                assets.open("tc2sc.cin"), StandardCharsets.UTF_8))) {
            Map<Character, Character> mappings = new HashMap<>();
            boolean inDefinitions = false;
            for (String line; (line = reader.readLine()) != null; ) {
                if (line.equals("%chardef begin")) {
                    inDefinitions = true;
                } else if (line.equals("%chardef end")) {
                    break;
                } else if (inDefinitions && line.length() == 3 && line.charAt(1) == '\t'
                        && isHan(line.charAt(0))) {
                    mappings.put(line.charAt(0), line.charAt(2));
                }
            }
            return new SimplifiedChineseOutput(mappings);
        } catch (IOException error) {
            Log.e("KeyKey", "Unable to read the traditional-to-simplified conversion table", error);
            return new SimplifiedChineseOutput(Map.of());
        }
    }

    private static boolean isHan(char character) {
        return (character >= '\u3400' && character <= '\u9fff')
                || (character >= '\uf900' && character <= '\ufaff');
    }

    String convert(String text) {
        StringBuilder output = null;
        for (int index = 0; index < text.length(); index++) {
            Character replacement = mappings.get(text.charAt(index));
            if (replacement == null) continue;
            if (output == null) output = new StringBuilder(text);
            output.setCharAt(index, replacement);
        }
        return output == null ? text : output.toString();
    }
}
