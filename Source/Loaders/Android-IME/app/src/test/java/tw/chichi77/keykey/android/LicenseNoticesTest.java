package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import java.io.IOException;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

public final class LicenseNoticesTest {
    private static JSONObject component(String id, String owner) throws org.json.JSONException {
        return new JSONObject().put("id", id).put("name", id).put("license", "MIT")
                .put("attribution", owner).put("source", "upstream")
                .put("licenseIDs", new JSONArray().put("shared"));
    }

    private static JSONObject catalog(String body) throws org.json.JSONException {
        return new JSONObject().put("schemaVersion", 1)
                .put("components", new JSONArray().put(component("A", "Copyright Alice")))
                .put("licenses", new JSONArray().put(new JSONObject().put("id", "shared").put("text", body)));
    }

    @Test public void sharedTermsKeepEachComponentsOwnCopyright() throws Exception {
        String terms = "Full permission and conditions：完整保留。";
        JSONObject catalog = catalog(terms);
        catalog.getJSONArray("components").put(component("B", "Copyright Bob"));
        var documents = LicenseNotices.parse(catalog.toString());
        assertEquals(2, documents.size());
        assertTrue(documents.get(0).text().contains("Copyright Alice"));
        assertFalse(documents.get(0).text().contains("Copyright Bob"));
        assertTrue(documents.get(1).text().contains("Copyright Bob"));
        assertTrue(documents.get(0).text().endsWith(terms));
        assertTrue(documents.get(1).text().endsWith(terms));
    }

    @Test public void longUnicodeNoticeIsNotTruncatedOrInterpretedAsMarkup() throws Exception {
        String body = "完整授權\n<script>literal text</script>".repeat(5000);
        assertTrue(LicenseNotices.parse(catalog(body).toString()).get(0).text().endsWith(body));
    }

    @Test(expected = IOException.class)
    public void missingReferencedTermsCannotBePresentedAsComplete() throws Exception {
        JSONObject catalog = catalog("Terms");
        catalog.getJSONArray("components").getJSONObject(0).put("licenseIDs", new JSONArray().put("missing"));
        LicenseNotices.parse(catalog.toString());
    }
}
