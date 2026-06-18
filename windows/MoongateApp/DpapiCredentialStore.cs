using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Moongate.Core;

namespace Moongate.App;

/// <summary>
/// Windows DPAPI 凭证存储（SEC-CRED-001）：每个值用当前用户密钥加密（ProtectedData，CurrentUser），
/// 密文以 base64 存进 %APPDATA%\Moongate\credentials.dat。换用户/换机无法解密；明文绝不落 settings.json。
/// </summary>
public sealed class DpapiCredentialStore : ICredentialStore
{
    private readonly string _path;
    private readonly object _lock = new();

    public DpapiCredentialStore(string? path = null)
        => _path = path ?? Path.Combine(AppSettings.SupportDirectory, "credentials.dat");

    public string? Get(string key)
    {
        lock (_lock)
        {
            var map = LoadMap();
            if (!map.TryGetValue(key, out var b64)) return null;
            try
            {
                var bytes = ProtectedData.Unprotect(
                    Convert.FromBase64String(b64), optionalEntropy: null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(bytes);
            }
            catch
            {
                // 解密失败（换用户/数据损坏）：当作不存在，不抛。
                return null;
            }
        }
    }

    public void Set(string key, string value)
    {
        lock (_lock)
        {
            var map = LoadMap();
            var protectedBytes = ProtectedData.Protect(
                Encoding.UTF8.GetBytes(value), optionalEntropy: null, DataProtectionScope.CurrentUser);
            map[key] = Convert.ToBase64String(protectedBytes);
            SaveMap(map);
        }
    }

    public void Delete(string key)
    {
        lock (_lock)
        {
            var map = LoadMap();
            if (map.Remove(key)) SaveMap(map);
        }
    }

    private Dictionary<string, string> LoadMap()
    {
        try
        {
            if (!File.Exists(_path)) return new(StringComparer.Ordinal);
            return JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(_path))
                ?? new(StringComparer.Ordinal);
        }
        catch
        {
            return new(StringComparer.Ordinal);
        }
    }

    private void SaveMap(Dictionary<string, string> map)
    {
        var dir = Path.GetDirectoryName(_path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var temp = _path + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(map));
            File.Move(temp, _path, overwrite: true);
        }
        catch
        {
            try { File.Delete(temp); } catch { /* 忽略 */ }
            throw;
        }
    }
}
