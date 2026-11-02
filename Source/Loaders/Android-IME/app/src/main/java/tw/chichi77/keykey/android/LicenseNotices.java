package tw.chichi77.keykey.android;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Reads the same component/shared-terms schema used by the iOS frontend. */
final class LicenseNotices {
    static final String ASSET = "licenses/Guanyinma-Notices.json";
    record Document(String title, String source, String text) {}

    static List<Document> parse(String text) throws IOException {
        try {
            JSONObject catalog = new JSONObject(text);
            if (catalog.getInt("schemaVersion") != 1) throw new IOException("Unsupported notice schema");
            Map<String, String> terms = new HashMap<>();
            JSONArray licenses = catalog.getJSONArray("licenses");
            for (int i = 0; i < licenses.length(); i++) {
                JSONObject item = licenses.getJSONObject(i);
                String body = item.getString("text");
                if (body.trim().isEmpty() || terms.put(item.getString("id"), body) != null) {
                    throw new IOException("Empty or duplicate license terms");
                }
            }
            List<Document> documents = new ArrayList<>();
            Set<String> identities = new HashSet<>();
            JSONArray components = catalog.getJSONArray("components");
            for (int i = 0; i < components.length(); i++) {
                JSONObject item = components.getJSONObject(i);
                if (!identities.add(item.getString("id"))) throw new IOException("Duplicate component");
                StringBuilder body = new StringBuilder(item.getString("attribution"));
                body.append("\n\n").append(item.getString("source"));
                JSONArray references = item.getJSONArray("licenseIDs");
                if (references.length() == 0) throw new IOException("Missing component terms");
                for (int j = 0; j < references.length(); j++) {
                    String license = terms.get(references.getString(j));
                    if (license == null) throw new IOException("Missing referenced license");
                    body.append("\n\n").append(license);
                }
                documents.add(new Document(item.getString("name"), item.getString("license"), body.toString()));
            }
            if (documents.isEmpty()) throw new IOException("No notice components");
            return java.util.Collections.unmodifiableList(documents);
        } catch (JSONException error) {
            throw new IOException("Invalid component catalog", error);
        }
    }
}
