systemenhance
系统优化脚本
系统优化脚本 systemenhance 旨在帮助用户快速优化和配置系统，特别适合新手用户。以下是其主要功能和使用方法。

功能
更新系统
安装常用组件
解决常见缺少命令的问题，如 sudo、wget 等，确保脚本顺利运行。
IPv4/IPv6 配置
支持双栈网络，可选择网络优先级。
修改 SSH 端口
增强系统安全性。
开启防火墙和 Fail2Ban
自动开放正在使用的端口，包括 SSH 端口。
如果安装新服务导致端口被防火墙阻挡，运行脚本即可自动开放相关端口。
调整时区
调整 SWAP 大小
启用 BBR
提升网络性能。
清理系统垃圾
使用方法
运行以下一键命令即可执行所有优化步骤：

bash
复制代码
wget -qO /tmp/systemenhance.sh https://raw.githubusercontent.com/Vincentkeio/systemenhance/refs/heads/main/systemenhance.sh && sudo chmod +x /tmp/systemenhance.sh && sudo bash /tmp/systemenhance.sh
注意：如果系统中没有 sudo 权限，可以移除命令中的 sudo，使用以下命令：

bash
复制代码
wget -qO /tmp/systemenhance.sh https://raw.githubusercontent.com/Vincentkeio/systemenhance/refs/heads/main/systemenhance.sh && chmod +x /tmp/systemenhance.sh && bash /tmp/systemenhance.sh
示例
使用 sudo 的安装命令：
bash
复制代码
wget -qO /tmp/systemenhance.sh https://raw.githubusercontent.com/Vincentkeio/systemenhance/refs/heads/main/systemenhance.sh \
&& sudo chmod +x /tmp/systemenhance.sh \
&& sudo bash /tmp/systemenhance.sh
无 sudo 权限的安装命令：
bash
复制代码
wget -qO /tmp/systemenhance.sh https://raw.githubusercontent.com/Vincentkeio/systemenhance/refs/heads/main/systemenhance.sh \
&& chmod +x /tmp/systemenhance.sh \
&& bash /tmp/systemenhance.sh
贡献
欢迎贡献代码、提出建议或报告问题。请访问 GitHub 仓库 获取更多信息。

许可证
本项目采用 MIT 许可证。

感谢使用 systemenhance，祝您使用愉快！
