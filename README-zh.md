	    这个项目是用于发布自己的jar包到远程仓库，并且使用git或github作为maven镜像仓库。目前，github可以使用site-maven-plugin完成jar包部署，也可使用github的package功能，但是git没有类似的插件和功能。于是，我们直接使用代码仓库作为maven的镜像仓库来放置自己开发的jar包。因此，本项目结合maven插件，提供了一种通用的方式将jar包推送到git或github平台。

# 快速开始

1.下载deploy.sh和ssh-auth-helper.exp，并将其放到本地目录。例如：/home/script。

2.在项目中配置maven插件。

1）maven-antrun-plugin

此插件用于在部署前清空本地仓库。

```xml
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-antrun-plugin</artifactId>
  <version>3.0.0</version>
  <executions>
    <execution>
      <id>clean-target-directory</id>
      <phase>prepare-package</phase>
      <goals>
        <goal>run</goal>
      </goals>
      <configuration>
        <target>
          <!-- clean target directory -->
          <delete dir="${project.basedir}/repo"/>
        </target>
      </configuration>
    </execution>
  </executions>
</plugin>
```

2）maven-source-plugin

此插件用于在部署时附上项目源码。

```xml
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-source-plugin</artifactId>
  <version>3.2.1</version>
  <executions>
    <execution>
      <id>attach-sources</id>
      <goals>
        <goal>jar-no-fork</goal>
      </goals>
    </execution>
  </executions>
</plugin>
```

3）maven-deploy-plugin

此插件用于生成jar包到本地仓库。

```xml
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-deploy-plugin</artifactId>
  <version>2.7</version>
  <configuration>
  <altDeploymentRepository>maven.repo::default::file://${project.basedir}/repo</altDeploymentRepository>
  </configuration>
</plugin>
```

4）exec-maven-plugin

​       此插件作用是执行脚本。此脚本支持解析git和github的ssh协议和https协议。推送代码之前，会从maven配置文件读取“server-id”配置作为授权凭证，如果配置的“server-id”未在maven配置文件中找到，脚本报错。如果协议类型是ssh，使用“server”配置的“privateKey”路径添加ssh代理，然后根据提示，脚本自动输入“passphrase”配置的密码；如果协议类型是https，使用git凭据管理器。git凭据管理器默认会在第一次认证时弹出弹框，为自动输入用户名和密码，我们通过修改git的全局配置，使其优先从文件获取认证信息(git读取认证信息的顺序可查看https://git-scm.com/book/en/v2)。认证通过后，拉取远程仓库的jar包，并与本地仓库的jar包进行合并，使用“--messge”的信息作为本次发布jar包的信息，然后推送本地仓库的jar包到远程分支。

```xml
<plugin>
  <groupId>org.codehaus.mojo</groupId>
  <artifactId>exec-maven-plugin</artifactId>
  <version>3.0.0</version>
  <executions>
    <execution>
      <id>add-executable-permission</id>
      <phase>deploy</phase>
      <goals>
        <goal>exec</goal>
      </goals>
      <configuration>
        <executable>chmod</executable>
        <arguments>
          <argument>+x</argument>
          <argument>/home/script/deploy.sh</argument>
        </arguments>
      </configuration>
    </execution>
    <execution>
    	<id>push-packages-to-github-repo</id>
     	<phase>deploy</phase>
      <goals>
        <goal>exec</goal>
      </goals>
      <configuration>
        <basedir>${project.basedir}/repo</basedir>
        <executable>/home/script/deploy.sh</executable>
        <arguments>
          <argument>--branch</argument>
          <argument>main</argument>
          <argument>--message</argument>
          <argument>Release ${project.groupId}:${build.finalName}.${project.packaging}</argument>
          <argument>--url</argument>
          <!--<argument>https://github.com/youername/mvn-repo</argument>-->
          <argument>git@github.com:youername/mvn-repo.git</argument>
          <argument>--server-id</argument>
          <argument>github-ssh</argument>
        </arguments>
      </configuration>
    </execution>
    <execution>
      <id>push-packages-to-gitee-repo</id>
      <phase>deploy</phase>
      <goals>
        <goal>exec</goal>
      </goals>
      <configuration>
        <basedir>${project.basedir}/repo</basedir>
        <executable>/home/script/deploy.sh</executable>
        <arguments>
          <argument>--branch</argument>
          <argument>master</argument>
          <argument>--path</argument>
          <argument>/repo</argument>
          <argument>--message</argument>
          <argument>Release ${project.groupId}:${build.finalName}.${project.packaging}</argument>
          <argument>--url</argument>
          <argument>https://gitee.com/youername/mvn-repo</argument>
          <!--<argument>git@gitee.com:youername/mvn-repo.git</argument>-->
          <argument>--server-id</argument>
          <argument>gitee</argument>
        </arguments>
      </configuration>
    </execution>
  </executions>
</plugin>
```

5)部署

```shell
mvn clean deploy
```

