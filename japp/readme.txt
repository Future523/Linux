1、创建工程：sh service.sh create tuan_item
2、cd tuan_item; vi setting.sh
3、修改MAIN_CLASS_NAME字段指定main函数所在jar包（maven打包名）
4、修改其他属性字段，JAVA_APP_OPTS用来设置启动参数
5、修改logs软连接
6、重启命令 ：sh service.sh restart tuan_item