namespace Moongate.Core;

/// <summary>
/// 凭证安全存储抽象（SEC-CRED-001）：API Token 不再明文落进 settings.json，改存平台安全存储。
/// 实现由 App 层注入（Windows = DPAPI）；Core 默认用内存实现（CLI/测试场景）。
/// </summary>
public interface ICredentialStore
{
    /// <summary>取凭证；不存在返回 null。</summary>
    string? Get(string key);
    /// <summary>写入/覆盖凭证。失败应抛异常（调用方据此保证「迁移失败不丢旧值」）。</summary>
    void Set(string key, string value);
    /// <summary>删除凭证（不存在时静默）。</summary>
    void Delete(string key);
}

/// <summary>进程内内存实现：Core 默认值、单测注入用。不持久化。</summary>
public sealed class InMemoryCredentialStore : ICredentialStore
{
    private readonly Dictionary<string, string> _items = new(StringComparer.Ordinal);
    public string? Get(string key) => _items.TryGetValue(key, out var v) ? v : null;
    public void Set(string key, string value) => _items[key] = value;
    public void Delete(string key) => _items.Remove(key);
}
