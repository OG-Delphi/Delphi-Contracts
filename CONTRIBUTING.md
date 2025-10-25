# Contributing to Delphi

Thank you for considering contributing to Delphi! This document outlines the process and guidelines.

## 🤝 How to Contribute

### Reporting Bugs

1. **Search existing issues** to avoid duplicates
2. **Include details**:
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment (OS, browser, wallet)
   - Contract addresses (if testnet/mainnet)
3. **Use the bug report template** when creating an issue

### Suggesting Features

1. **Check the roadmap** in README.md first
2. **Open a discussion** in GitHub Discussions before creating an issue
3. **Explain the use case** and why it benefits users
4. **Consider backwards compatibility**

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/your-feature-name`
3. **Make your changes**:
   - Follow existing code style
   - Add tests for new functionality
   - Update documentation
4. **Run tests**: `forge test` (all must pass)
5. **Format code**: `forge fmt`
6. **Commit with clear messages**: `git commit -m "feat: add market template for price ranges"`
7. **Push to your fork**: `git push origin feature/your-feature-name`
8. **Open a Pull Request** with a clear description

## 🧪 Testing Guidelines

### Smart Contracts

- **Write tests** for all new functions
- **Test edge cases** (zero values, overflows, reverts)
- **Use descriptive test names**: `test_BuyRevertsWhenMarketLocked()`
- **Aim for >90% coverage**

### Running Tests

```bash
cd contracts
forge test                    # Run all tests
forge test -vvv              # Verbose output
forge test --gas-report      # Gas usage
forge coverage               # Coverage report
```

## 📝 Code Style

### Solidity

- **Follow Solidity style guide**: https://docs.soliditylang.org/style-guide.html
- **Use NatSpec comments** for all public functions
- **Format with forge**: `forge fmt`
- **Name conventions**:
  - Contracts: `PascalCase`
  - Functions: `camelCase`
  - Variables: `camelCase`
  - Constants: `UPPER_SNAKE_CASE`
  - Private: prefix with `_`

### TypeScript (Extension)

- **Use ESLint** and **Prettier**
- **Type everything** (no `any`)
- **Use async/await** over promises
- **Handle errors explicitly**

## 🔐 Security

### Before Submitting

- **No hardcoded private keys** or secrets
- **No console.log** in production code
- **Validate all inputs** in public functions
- **Use SafeMath** for arithmetic (or Solidity 0.8+)
- **Follow checks-effects-interactions** pattern

### Security Issues

**DO NOT** open public issues for security vulnerabilities.

Email: security@yourproject.com

## 📚 Documentation

### When to Update Docs

- New features → Update README.md
- Contract changes → Update contracts/README.md
- Deployment changes → Update contracts/DEPLOYMENT.md
- Access control changes → Update contracts/ACCESS_CONTROL.md

### Documentation Style

- **Be clear and concise**
- **Include code examples**
- **Link to relevant sections**
- **Use proper markdown formatting**

## 🎯 Areas Needing Help

### High Priority

- [ ] Chrome extension frontend (React + TypeScript)
- [ ] The Graph subgraph implementation
- [ ] Additional market templates (price ranges, multiple outcomes)
- [ ] Gas optimization in CPMM math
- [ ] Integration tests for full market lifecycle

### Medium Priority

- [ ] UI/UX design for extension
- [ ] Mobile PWA version
- [ ] Additional oracle integrations (Pyth, API3)
- [ ] Market analytics dashboard
- [ ] Governance token design

### Nice to Have

- [ ] Multi-language support
- [ ] Dark mode for extension
- [ ] Social sharing features
- [ ] Historical market data export
- [ ] Trading bots / API

## 🚀 Development Workflow

### 1. Set Up Environment

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/delphi.git
cd delphi

# Add upstream remote
git remote add upstream https://github.com/ORIGINAL_OWNER/delphi.git

# Install dependencies
cd contracts && forge install
```

### 2. Create Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 3. Make Changes

- Write code
- Write tests
- Update docs

### 4. Test Locally

```bash
forge test
forge coverage
forge fmt --check
```

### 5. Commit & Push

```bash
git add .
git commit -m "feat: descriptive message"
git push origin feature/your-feature-name
```

### 6. Open Pull Request

- Go to GitHub
- Click "New Pull Request"
- Select your feature branch
- Fill out the PR template
- Request review

## 📋 PR Review Process

### What We Look For

1. **Functionality**: Does it work as intended?
2. **Tests**: Are there tests? Do they pass?
3. **Security**: Any vulnerabilities introduced?
4. **Gas Efficiency**: Is the code optimized?
5. **Code Quality**: Is it readable and maintainable?
6. **Documentation**: Is it documented?

### Review Timeline

- Simple fixes: 1-2 days
- New features: 3-7 days
- Major changes: 1-2 weeks

### After Approval

- Maintainer will merge your PR
- Your contribution will be in the next release
- You'll be added to CONTRIBUTORS.md (if first contribution)

## 🏅 Recognition

Contributors are recognized in:
- CONTRIBUTORS.md file
- Release notes (for significant contributions)
- GitHub contributor graph

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License.

## ❓ Questions?

- Open a discussion in GitHub Discussions
- Ask in Discord (link in README)
- Email: contribute@yourproject.com

---

Thank you for making Delphi better! 🚀

