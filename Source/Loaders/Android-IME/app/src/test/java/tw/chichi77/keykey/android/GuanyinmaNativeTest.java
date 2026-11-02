/* Copyright (c) 2026 Chui-Ping Cheng. MIT License. */
package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Assume;
import org.junit.BeforeClass;
import org.junit.Test;

/** Real JNI transport checks, without an Android runtime or frontend. */
public final class GuanyinmaNativeTest {
    private static String model;
    private static final String TABLE = "{\"method\":\"cangjie\",\"cangjie\":{\"realtime\":true}}";

    @BeforeClass public static void nativeFixture() {
        String library = System.getProperty("keykey.guanyinma.library");
        Assume.assumeTrue("Host JNI must be explicitly prepared", library != null);
        assertTrue("Configured host JNI is missing", new File(library).isFile());
        model = System.getProperty("keykey.smart.database");
        assertNotNull("Configured model is missing", model);
        assertTrue(new File(model).isFile());
    }

    @Test public void standardUtf8PreservesSupplementaryInputAndCallbackCandidates() {
        List<String> seen = new ArrayList<>();
        try (GuanyinmaNative input = GuanyinmaNative.open(model, TABLE, text -> { seen.add(text); return true; })) {
            input.apply("{\"type\":\"character\",\"text\":\"h\"}");
            input.apply("{\"type\":\"character\",\"text\":\"k\"}");
            assertTrue("Predicate must receive real supplementary Unicode", seen.contains("𥫜"));
            String literal = input.apply("{\"type\":\"direct_text\",\"text\":\"喬🙂\"}");
            assertTrue(literal.contains("\"commit\":\"喬🙂\""));
            assertTrue(input.userData().contains("\"kind\":\"user_data\""));
        }
    }

    @Test public void coreErrorsBecomeRuntimeExceptionsAndLeaveTheSessionUsable() {
        try (GuanyinmaNative input = GuanyinmaNative.open(model, TABLE, null)) {
            input.apply("{\"type\":\"character\",\"text\":\"a\"}");
            String before = input.snapshot();
            assertThrows(RuntimeException.class, () -> input.apply("{\"type\":\"not_a_real_operation\"}"));
            assertEquals(before, input.snapshot());
            assertTrue(input.apply("{\"type\":\"direct_text\",\"text\":\"A\"}").contains("\"commit\":\"A\""));
        }
    }

    @Test public void closedTokensCannotReferToAnotherSession() throws Exception {
        GuanyinmaNative first = GuanyinmaNative.open(model, TABLE, null);
        Field field = GuanyinmaNative.class.getDeclaredField("handle");
        field.setAccessible(true);
        long stale = field.getLong(first);
        first.close();
        first.close();
        assertThrows(IllegalStateException.class, first::snapshot);
        try (GuanyinmaNative second = GuanyinmaNative.open(model, TABLE, null)) {
            Method read = GuanyinmaNative.class.getDeclaredMethod("nativeRead", long.class, int.class, byte[].class);
            read.setAccessible(true);
            InvocationTargetException failure = assertThrows(InvocationTargetException.class,
                () -> read.invoke(null, stale, 1, null));
            assertTrue(failure.getCause() instanceof RuntimeException);
            assertTrue(second.snapshot().contains("\"method\":\"cangjie\""));
        }
    }

    @Test public void callbackExceptionsKeepTheirCauseAndInvalidateFurtherOperations() {
        IllegalStateException cause = new IllegalStateException("glyph fixture failure");
        try (GuanyinmaNative input = GuanyinmaNative.open(model, TABLE, text -> { throw cause; })) {
            RuntimeException failure = assertThrows(RuntimeException.class,
                () -> input.apply("{\"type\":\"character\",\"text\":\"a\"}"));
            assertSame(cause, failure.getCause());
            assertThrows(RuntimeException.class, input::snapshot);
        }
    }

    @Test(timeout = 5000) public void callbacksCannotReenterTheirOwnSession() {
        AtomicReference<GuanyinmaNative> self = new AtomicReference<>();
        try (GuanyinmaNative input = GuanyinmaNative.open(model, TABLE, text -> {
            self.get().snapshot();
            return true;
        })) {
            self.set(input);
            RuntimeException failure = assertThrows(RuntimeException.class,
                () -> input.apply("{\"type\":\"character\",\"text\":\"a\"}"));
            assertTrue(failure.getCause() instanceof RuntimeException);
        }
    }

    @Test public void unpairedUtf16SurrogatesAreRejectedWithoutReplacementText() {
        try (GuanyinmaNative input = GuanyinmaNative.open(model, TABLE, null)) {
            String before = input.snapshot();
            assertThrows(IllegalArgumentException.class, () -> input.apply("\uD800"));
            assertEquals(before, input.snapshot());
        }
    }
}
