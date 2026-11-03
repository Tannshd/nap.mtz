package io.mtzapply12;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.widget.CheckBox;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.text.method.ScrollingMovementMethod;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.lang.reflect.Method;

import rikka.shizuku.Shizuku;

public class MainActivity extends Activity {
    private static final String REMOTE_SCRIPT = "/data/local/tmp/mtzapply12.sh";
    private EditText pathEdit;
    private TextView out;
    private Button run;
    private CheckBox autoBox;
    private Uri pickedUri;
    private static final int REQ_PICK = 77;
    private static final String PICKED_REMOTE = "/data/local/tmp/picked.mtz";

    private final Shizuku.OnRequestPermissionResultListener permListener =
            (requestCode, grantResult) -> {
                if (grantResult == PackageManager.PERMISSION_GRANTED) {
                    runScript();
                } else {
                    log("Shizuku: bạn đã từ chối quyền.");
                }
            };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        int pad = (int) (16 * getResources().getDisplayMetrics().density);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        TextView hint = new TextView(this);
        hint.setText("File .mtz (đường dẫn trong bộ nhớ máy):");
        root.addView(hint);

        pathEdit = new EditText(this);
        pathEdit.setText("/sdcard/MIUI/theme/MtzApply.mtz");
        pathEdit.setSingleLine(true);
        root.addView(pathEdit);

        Button pick = new Button(this);
        pick.setText("Chọn file .mtz");
        pick.setOnClickListener(v -> {
            Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            i.addCategory(Intent.CATEGORY_OPENABLE);
            i.setType("*/*");
            startActivityForResult(i, REQ_PICK);
        });
        root.addView(pick);

        autoBox = new CheckBox(this);
        autoBox.setText("Tự động bấm \"Áp dụng\"");
        autoBox.setChecked(true);
        root.addView(autoBox);

        run = new Button(this);
        run.setText("Áp theme (qua Shizuku)");
        run.setOnClickListener(v -> onRun());
        root.addView(run);

        out = new TextView(this);
        out.setTextIsSelectable(true);
        out.setMovementMethod(new ScrollingMovementMethod());
        out.setTypeface(android.graphics.Typeface.MONOSPACE);
        out.setTextSize(12);
        root.addView(out, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        setContentView(root);
        Shizuku.addRequestPermissionResultListener(permListener);
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == REQ_PICK && res == RESULT_OK && data != null && data.getData() != null) {
            pickedUri = data.getData();
            String name = "file đã chọn";
            try (Cursor c = getContentResolver().query(pickedUri, null, null, null, null)) {
                if (c != null && c.moveToFirst()) {
                    int idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                    if (idx >= 0) name = c.getString(idx);
                }
            } catch (Throwable ignored) { }
            pathEdit.setText("[đã chọn] " + name);
        }
    }

    @Override
    protected void onDestroy() {
        Shizuku.removeRequestPermissionResultListener(permListener);
        super.onDestroy();
    }

    private void onRun() {
        try {
            if (!Shizuku.pingBinder()) {
                log("Shizuku chưa chạy. Mở app Shizuku và bấm Start rồi thử lại.");
                return;
            }
            if (Shizuku.isPreV11()) {
                log("Shizuku quá cũ, cần bản v11 trở lên.");
                return;
            }
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                runScript();
            } else if (Shizuku.shouldShowRequestPermissionRationale()) {
                log("Bạn đã chặn quyền. Vào app Shizuku > Ứng dụng được ủy quyền, bật MtzApply-12.");
            } else {
                Shizuku.requestPermission(12);
            }
        } catch (Throwable t) {
            log("Lỗi Shizuku: " + t);
        }
    }

    private void runScript() {
        run.setEnabled(false);
        String typed = pathEdit.getText().toString().trim();
        final boolean usePicked = pickedUri != null && typed.startsWith("[đã chọn]");
        final String path = usePicked ? PICKED_REMOTE : typed;
        final boolean auto = autoBox.isChecked();
        out.setText("");
        new Thread(() -> {
            try {
                // 1) chép script vào /data/local/tmp bằng quyền shell
                byte[] script = readAsset("mtzapply12.sh");
                Process w = newProcess(new String[]{"sh", "-c", "cat > " + REMOTE_SCRIPT});
                OutputStream os = w.getOutputStream();
                os.write(script);
                os.close();
                w.waitFor();

                if (usePicked) {
                    log("Đang chép file đã chọn...");
                    Process cp = newProcess(new String[]{"sh", "-c", "cat > " + PICKED_REMOTE});
                    OutputStream co = cp.getOutputStream();
                    try (InputStream ci = getContentResolver().openInputStream(pickedUri)) {
                        byte[] buf = new byte[65536];
                        int n;
                        while ((n = ci.read(buf)) > 0) co.write(buf, 0, n);
                    }
                    co.close();
                    cp.waitFor();
                }

                // 2) chạy script, in kết quả ra màn hình
                Process p = newProcess(new String[]{"sh", "-c",
                        "sh " + REMOTE_SCRIPT + " '" + path.replace("'", "'\\''") + "'"
                        + (auto ? " --auto" : "") + " 2>&1"});
                BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
                String line;
                while ((line = r.readLine()) != null) log(line);
                int code = p.waitFor();
                log("[exit " + code + "]");
            } catch (Throwable t) {
                log("Lỗi: " + t);
            } finally {
                runOnUiThread(() -> run.setEnabled(true));
            }
        }).start();
    }

    // Shizuku.newProcess là private từ API 13 -> gọi bằng reflection (cách phổ biến)
    private static Process newProcess(String[] cmd) throws Exception {
        Method m = Shizuku.class.getDeclaredMethod(
                "newProcess", String[].class, String[].class, String.class);
        m.setAccessible(true);
        return (Process) m.invoke(null, new Object[]{cmd, null, null});
    }

    private byte[] readAsset(String name) throws Exception {
        try (InputStream in = getAssets().open(name)) {
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            return bo.toByteArray();
        }
    }

    private void log(String s) {
        runOnUiThread(() -> out.append(s + "\n"));
    }
}
