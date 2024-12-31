# systemenhance
系统优化脚本
功能：  
一、更新系统；  
二、安装常用组件（许多小白经常缺少sudo wget之类的跑不了脚本，遇到缺少command的情况刷一下本脚本就行）；  
三、开启防火墙（但目前使用中的端口会自动开放，包括所有正在监听或占用的端口，特别是SSH，如果你安装了某些服务后端口不通被防火墙挡住的话，也可以运行本脚本，会自动帮你打开）和fail2ban；  
四、调整时区；  
五、调整SWAP大小； 
六、打开BBR
七、清理垃圾  
使用方法：运行一键命令  
`wget -qO /tmp/systemenhance.sh https://raw.githubusercontent.com/Vincentkeio/systemenhance/refs/heads/main/systemenhance.sh && sudo chmod +x /tmp/systemenhance.sh && sudo bash /tmp/systemenhance.sh`

