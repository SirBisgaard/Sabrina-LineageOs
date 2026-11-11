import android.media.MediaDrm;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.UUID;

public class CastProbe {
    static final UUID CASTKEY = UUID.fromString("bcb481cb-a1d5-42af-b1e3-7bff1473eb85");
    static final UUID WIDEVINE = UUID.fromString("edef8ba9-79d6-4ace-a3c8-27dcd51d21ed");

    static String sha1(byte[] data) throws Exception {
        StringBuilder sb = new StringBuilder();
        for (byte b : MessageDigest.getInstance("SHA-1").digest(data)) sb.append(String.format("%02x", b));
        return sb.toString();
    }

    static void property(MediaDrm drm, String name) {
        try {
            byte[] value = drm.getPropertyByteArray(name);
            System.out.println(name + ": " + value.length + " bytes sha1=" + sha1(value));
        } catch (Throwable t) {
            System.out.println(name + ": FAILED " + t);
        }
    }

    static void sign(MediaDrm drm, String keyFile, String algorithm) {
        byte[] session = null;
        try {
            byte[] key = Files.readAllBytes(Paths.get(keyFile));
            byte[] message = MessageDigest.getInstance("SHA-256").digest("cast-probe".getBytes());
            session = drm.openSession();
            byte[] signature = (byte[]) MediaDrm.class.getMethod("signRSA", byte[].class, String.class, byte[].class, byte[].class).invoke(drm, session, algorithm, key, message);
            System.out.println("sign " + keyFile + " " + algorithm + ": OK " + signature.length + " bytes");
        } catch (Throwable t) {
            Throwable c = t.getCause() != null ? t.getCause() : t;
            System.out.println("sign " + keyFile + " " + algorithm + ": FAILED " + c);
        } finally {
            if (session != null) drm.closeSession(session);
        }
    }


    static byte[] uuidBytes(UUID uuid) {
        java.nio.ByteBuffer b = java.nio.ByteBuffer.allocate(16);
        b.putLong(uuid.getMostSignificantBits());
        b.putLong(uuid.getLeastSignificantBits());
        return b.array();
    }

    static MediaDrm open(UUID uuid) throws Exception {
        java.lang.reflect.Field unsafeField = Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe");
        unsafeField.setAccessible(true);
        Object unsafe = unsafeField.get(null);
        MediaDrm drm = (MediaDrm) unsafe.getClass().getMethod("allocateInstance", Class.class).invoke(unsafe, MediaDrm.class);
        java.lang.reflect.Method setup = MediaDrm.class.getDeclaredMethod("native_setup", Object.class, byte[].class, String.class);
        setup.setAccessible(true);
        setup.invoke(drm, new java.lang.ref.WeakReference<>(drm), uuidBytes(uuid), "com.android.shell");
        for (java.lang.reflect.Field f : MediaDrm.class.getDeclaredFields()) {
            if (java.lang.reflect.Modifier.isStatic(f.getModifiers())) continue;
            f.setAccessible(true);
            if (f.get(drm) != null) continue;
            if (java.util.Map.class.isAssignableFrom(f.getType())) f.set(drm, new java.util.concurrent.ConcurrentHashMap<>());
            else if (java.util.List.class.isAssignableFrom(f.getType())) f.set(drm, new java.util.ArrayList<>());
        }
        return drm;
    }

    public static void main(String[] args) throws Exception {
        System.out.println("castkey supported: " + MediaDrm.isCryptoSchemeSupported(CASTKEY));
        System.out.println("widevine supported: " + MediaDrm.isCryptoSchemeSupported(WIDEVINE));
        MediaDrm drm = open(CASTKEY);
        property(drm, "castcert");
        property(drm, "castkey");
        for (int i = 0; i + 1 < args.length; i += 2) sign(drm, args[i], args[i + 1]);
    }
}
