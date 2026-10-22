using System;
using System.IO;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.ComponentModel;

// Windows CNG uses fixed-width IEEE P1363 signatures. Apple's Security API
// uses ASN.1 DER / X9.62. Convert strictly at this single boundary.
public static class GFCrypto {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool MoveFileEx(string existing, string destination, int flags);
    public static void AtomicReplace(string temporary, string destination) {
        // Both paths are in the same directory: rename with replacement and
        // write-through, without File.Replace's requirement to copy NTFS ACLs.
        if (!MoveFileEx(temporary, destination, 1 | 8)) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    public static byte[] Protect(byte[] data) {
        return ProtectedData.Protect(data, null, DataProtectionScope.CurrentUser);
    }
    public static byte[] Unprotect(byte[] data) {
        return ProtectedData.Unprotect(data, null, DataProtectionScope.CurrentUser);
    }
    public static byte[] NewPrivateKey() {
        var options = new CngKeyCreationParameters();
        options.ExportPolicy = CngExportPolicies.AllowPlaintextExport;
        using (var key = CngKey.Create(CngAlgorithm.ECDsaP256, null, options))
            return key.Export(CngKeyBlobFormat.EccPrivateBlob);
    }
    public static byte[] PublicPoint(byte[] privateBlob) {
        using (var key = CngKey.Import(privateBlob, CngKeyBlobFormat.EccPrivateBlob)) {
            var blob = key.Export(CngKeyBlobFormat.EccPublicBlob);
            var point = new byte[65]; point[0] = 4;
            Buffer.BlockCopy(blob, 8, point, 1, 64);
            return point;
        }
    }
    static byte[] Integer(byte[] raw, int start) {
        int first = start;
        while (first < start + 31 && raw[first] == 0) first++;
        int pad = raw[first] >= 128 ? 1 : 0;
        var result = new byte[2 + start + 32 - first + pad];
        result[0] = 2; result[1] = (byte)(result.Length - 2);
        Buffer.BlockCopy(raw, first, result, 2 + pad, start + 32 - first);
        return result;
    }
    public static byte[] ToDER(byte[] raw) {
        if (raw.Length != 64) throw new CryptographicException("Invalid P-256 signature");
        byte[] r = Integer(raw, 0), s = Integer(raw, 32);
        var result = new byte[2 + r.Length + s.Length];
        result[0] = 48; result[1] = (byte)(result.Length - 2);
        Buffer.BlockCopy(r, 0, result, 2, r.Length);
        Buffer.BlockCopy(s, 0, result, 2 + r.Length, s.Length);
        return result;
    }
    public static byte[] FromDER(byte[] der) {
        if (der.Length < 8 || der.Length > 72 || der[0] != 48 || der[1] != der.Length - 2)
            throw new CryptographicException("Invalid DER signature");
        var raw = new byte[64]; int offset = 2;
        for (int part = 0; part < 2; part++) {
            if (offset + 2 > der.Length || der[offset++] != 2) throw new CryptographicException("Invalid DER integer");
            int length = der[offset++];
            if (length < 1 || length > 33 || offset + length > der.Length || der[offset] >= 128)
                throw new CryptographicException("Invalid DER integer length/sign");
            if (length > 1 && der[offset] == 0) {
                if (der[offset + 1] < 128) throw new CryptographicException("Non-minimal DER integer");
                offset++; length--;
            }
            if (length > 32) throw new CryptographicException("Invalid P-256 integer");
            Buffer.BlockCopy(der, offset, raw, part * 32 + 32 - length, length);
            offset += length;
        }
        if (offset != der.Length) throw new CryptographicException("Trailing DER data");
        return raw;
    }
    public static byte[] Sign(byte[] privateBlob, byte[] data) {
        using (var key = CngKey.Import(privateBlob, CngKeyBlobFormat.EccPrivateBlob))
        using (var ecdsa = new ECDsaCng(key)) {
            ecdsa.HashAlgorithm = CngAlgorithm.Sha256;
            return ToDER(ecdsa.SignData(data));
        }
    }
    public static bool Verify(byte[] point, byte[] data, byte[] der) {
        if (point.Length != 65 || point[0] != 4) return false;
        var blob = new byte[72]; // BCRYPT_ECCKEY_BLOB, ECDSA_PUBLIC_P256_MAGIC
        blob[0] = 0x45; blob[1] = 0x43; blob[2] = 0x53; blob[3] = 0x31; blob[4] = 32;
        Buffer.BlockCopy(point, 1, blob, 8, 64);
        using (var key = CngKey.Import(blob, CngKeyBlobFormat.EccPublicBlob))
        using (var ecdsa = new ECDsaCng(key)) {
            ecdsa.HashAlgorithm = CngAlgorithm.Sha256;
            return ecdsa.VerifyData(data, FromDER(der));
        }
    }
}
