public class VintfProbe {
    public static void main(String[] args) throws Exception {
        Class<?> cls = Class.forName("android.os.VintfObject");
        java.lang.reflect.Method method = cls.getDeclaredMethod("verifyWithoutAvb");
        method.setAccessible(true);
        int result = ((Integer) method.invoke(null)).intValue();
        System.out.println("VINTF_RESULT=" + result);
        if (result != 0) System.exit(1);
    }
}
