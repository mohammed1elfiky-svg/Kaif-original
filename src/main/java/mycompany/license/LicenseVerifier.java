package mycompany.license;

import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Activation keys of Al-Kaif Al-Asli: "KAIF1.<payload>.<signature>", both parts base64url.
 * The payload is "key=value;key=value" (licensee, expires = yyyy-MM-dd or "never", users), signed with
 * SHA256withRSA by the private key of the vendor (tools/license, the private key is not in the repository).
 * Only the public key is here, so a key cannot be made from the source code.
 */
public final class LicenseVerifier {

    static final String PUBLIC_KEY =
            "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3iBCCwwA/6n2hg1cEkonmlXIEDGBVduNkElICTR9f4ok8W1qdIkgs9Qyc2LhL9/MKz323m2fc289xcx525YNoyRWbpT07wA1d5cZgGPHakaFQ07cur04/84OuqL6qqj6lwSirP5QZ7o2xDPAVR8jnqxw1giNnXicEHZldWXuG8N/686vgkdEMlGe2JJO2Sph2+YPUNcxpITI7qvq9YTs5Q9WmCGBwyjSyV4yjivlLkk2O17GDSgfmJkjb8vJWAa46PtCjqM8m86fn6VdRTDp2ZJXoV0t3Q7HEti+8VA1oUkjf0qdeyP58j/hqRLoXBekklf2t8iZjalwsfeHkY3BPQIDAQAB";

    private LicenseVerifier() {
    }

    /** Returns the fields of the payload when the signature is valid, otherwise null. */
    public static Map<String, String> verify(String key) {
        return verify(key, PUBLIC_KEY);
    }

    static Map<String, String> verify(String key, String publicKeyBase64) {
        if (key == null) return null;
        String[] parts = key.trim().split("\\.");
        if (parts.length != 3 || !"KAIF1".equals(parts[0])) return null;
        try {
            byte[] payload = Base64.getUrlDecoder().decode(parts[1]);
            byte[] signature = Base64.getUrlDecoder().decode(parts[2]);
            PublicKey publicKey = KeyFactory.getInstance("RSA")
                    .generatePublic(new X509EncodedKeySpec(Base64.getDecoder().decode(publicKeyBase64)));
            Signature verifier = Signature.getInstance("SHA256withRSA");
            verifier.initVerify(publicKey);
            verifier.update(payload);
            if (!verifier.verify(signature)) return null;
            Map<String, String> fields = new LinkedHashMap<>();
            for (String pair : new String(payload, StandardCharsets.UTF_8).split(";")) {
                int i = pair.indexOf('=');
                if (i > 0) fields.put(pair.substring(0, i).trim(), pair.substring(i + 1).trim());
            }
            return fields;
        } catch (Exception e) {
            return null;
        }
    }
}
