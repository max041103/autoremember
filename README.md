# 债务追踪 (autoremember)

一个基于 Flutter 的个人债务管理应用，帮助你追踪每一笔借款、自动计算利息、记录还款流水。

## ✨ 主要功能

### 📋 债务人管理
- **添加债务人**：记录借款人姓名、借款金额、借款日期
- **编辑/删除**：随时修改债务人信息或删除记录（含确认对话框防止误删）
- **列表概览**：首页展示所有债务人，清晰显示待还金额、借款日期、未结利息

### 💰 三种计息模式

| 模式 | 说明 |
|------|------|
| **A. 按日计息** | 设定年利率，系统按日自动计算利息（日利率 = 年利率 / 365） |
| **B. 月固定利息** | 设定每月固定利息金额，系统按月自动累加 |
| **C. 纯手动** | 不自动产生利息，完全由用户手动添加利息条目 |

系统会自动记录「计息基准日期」，每次进入债务人详情页时自动结算从上次基准日到当天的利息，避免重复计算。

### 📝 还款记录
- **智能还款拆分**：还款时自动优先偿还利息，剩余部分扣减本金
- **还款详情**：每条还款记录清晰展示利息部分和本金部分的金额
- **全部还清提示**：债务清零后显示 🎉 庆祝标识

### 🔧 手动调息
- 支持手动添加利息条目，适用于罚息、特殊调整等场景
- 可单独删除每条利息记录

### 📊 数据概览
- **首页卡片**：每个债务人显示名称首字母头像、借款金额、日期、未结利息、待还总额
- **详情页顶部**：展示当前本金、未结利息、借款总额三大指标
- **还清/待还状态**：已还清显示绿色 ✓，待还显示红色金额

### 🕐 流水时间轴
- 按时间倒序展示所有利息产生和还款记录
- 时间轴可视化设计，绿色圆点代表还款，红色圆点代表利息
- 每条记录可独立删除，带确认对话框

### 💾 本地持久化
- 所有数据通过 SharedPreferences 以 JSON 格式存储在本地
- 无需网络，隐私安全

### 🎨 界面设计
- Material Design 3 风格
- 自定义配色方案（主题色：深绿 #287d6f）
- 支持亮色模式
- 自定义金额输入键盘

## 📸 截图

<!-- 可在此处添加应用截图 -->

## 🛠 技术栈

- **框架**：Flutter 3.x
- **语言**：Dart
- **状态管理**：StatefulWidget + setState
- **数据存储**：SharedPreferences + JSON 序列化
- **UI**：Material Design 3

## 📁 项目结构

```
lib/
├── main.dart                      # 应用入口
├── models/
│   └── debtor.dart                # 数据模型（Debtor, Repayment, InterestEntry, DebtStore）
├── screens/
│   ├── home_page.dart             # 首页（债务人列表）
│   ├── debtor_detail_page.dart    # 债务人详情页（统计+流水时间轴）
│   └── add_debtor_dialog.dart     # 添加/编辑债务人对话框
├── utils/
│   ├── calculators.dart           # 利息计算引擎（按日/按月）
│   └── formatters.dart            # 格式化工具（日期、金额）
└── widgets/
    ├── amount_keypad.dart         # 自定义数字键盘
    ├── mini_stat.dart             # 迷你统计卡片组件
    ├── number_field.dart          # 数字输入字段
    └── repayment_editor.dart      # 还款/调息编辑器
```

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.0
- Dart >= 3.0
- Android Studio / VS Code

### 安装运行

```bash
# 克隆项目
git clone https://github.com/max041103/autoremember.git
cd autoremember

# 安装依赖
flutter pub get

# 运行应用
flutter run
```

### 构建 APK

```bash
flutter build apk --release
```

## 📄 许可证

MIT License

---

**autoremember** — 不要让借钱变成一笔糊涂账。