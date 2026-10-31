package tw.chichi77.keykey.android;

import static org.junit.Assert.*;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.view.View;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.List;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class KeyboardRenderingInstrumentedTest {
    @Test public void touchKeyboardRendersLiteralKeysAcrossLayoutsMethodsAndPlanes() {
        var instrumentation = InstrumentationRegistry.getInstrumentation();
        instrumentation.runOnMainSync(() -> {
            for (var mode : new BopomofoKeyboardView.Mode[] {
                    BopomofoKeyboardView.Mode.PORTRAIT, BopomofoKeyboardView.Mode.LANDSCAPE }) {
                var view = new BopomofoKeyboardView(instrumentation.getTargetContext());
                view.setMode(mode);
                for (var layout : BopomofoKeyboardLayout.values()) {
                    view.setKeyboardLayout(layout);
                    for (var method : ChineseInputMethod.values()) {
                        view.setChineseInputMethod(method);
                        for (var plane : InputEngine.InputMode.values()) {
                            for (boolean shifted : new boolean[] {false, true}) {
                                view.setState(List.of(), "", method == ChineseInputMethod.SMART,
                                        List.of(), 0, plane, shifted, false, false, false,
                                        0, 1, -1, InputFieldPolicy.DEFAULT);
                                view.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
                                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
                                view.layout(0, 0, view.getMeasuredWidth(), view.getMeasuredHeight());
                                assertTrue(view.getHeight() > 0);
                                Bitmap bitmap = Bitmap.createBitmap(view.getWidth(), view.getHeight(),
                                        Bitmap.Config.ARGB_8888);
                                try {
                                    view.draw(new Canvas(bitmap));
                                } finally {
                                    bitmap.recycle();
                                }
                            }
                        }
                    }
                }
            }
        });
    }
}
