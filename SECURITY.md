# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 3.x     | :white_check_mark: |
| < 3.0   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: alex@howells.me

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### What to Expect

- **Response**: Within 48 hours acknowledging receipt
- **Updates**: Every 5 business days on progress
- **Resolution**: Target 90 days for fix

### Disclosure Policy

- We follow coordinated disclosure
- Credit will be given to reporters (unless anonymity requested)
- We will not pursue legal action against good-faith reporters

## Security Best Practices

When contributing:
- Never commit secrets, tokens, or credentials
- OAuth `.credential` files are stored with chmod 600
- API key `.apikey` files are stored with chmod 600
- Keychain credentials are stored using macOS security best practices
