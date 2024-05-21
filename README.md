[English](https://github.com/plato-wei/maven-repository-deployment-tool/blob/main/README.md)|[简体中文](https://github.com/plato-wei/maven-repository-deployment-tool/blob/main/README-zh.md)

------

This project is for publishing your own jar packages to a remote repository and using git or github as a maven mirror repository. At present, github can use site-maven-plugin to complete jar package deployment, and can also use github's package function, but git does not have similar plug-ins and functions. Therefore, we directly use the code repository as a mirror repository for maven to place the jar packages we developed. Therefore, this project, combined with the maven plugin, provides a common way to push jar packages to git or github platforms.

# Quick Start

Step1: Download script deploy.sh and ssh-auth-helper.exp, and place them in a local directory.eg: /home/script.

Step2: Configure the maven plugin in your project.

1.maven-antrun-plugin

The maven-antrun-plugin is used to clean the local repository before deployment.

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

2.maven-source-plugin

If you need to generate source code along with the jar package, configure this plugin.

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

3.maven-deploy-plugin

The maven-deploy-plugin generates the jar package to the local repository.

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

4.exec-maven-plugin

  The exec-maven-plugin is used to execute scripts. This script supports parsing git and github's ssh and https protocols. Before pushing the code, the "server-id" configuration is read from the maven profile as an authorization credential. If the configured "--server-id" is not found in the maven profile, the script reports an error. If the protocol type is ssh, use the privateKey path configured in server to add an ssh proxy. Then, the script automatically enters the password configured in passphrase as prompted. If the protocol type is https, use git credential manager. By default, the git credential manager will pop up during the first authentication. To automatically input the user name and password, we modify the git global configuration so that git preferentially obtains the authentication information from files. (See https://git-scm.com/book/en/v2 for the order of git reading authentication information.) After the authentication is successful, the jar package of the remote warehouse is pulled and merged with the jar package of the local warehouse. The information of "--messge" is used as the information of the jar package for this release. Then, the jar package of the local warehouse is pushed to the remote branch.

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

script parameters:

--branch: specify the branch name to commit and push to

--path: specify the commit message.

--message: specify the repository url.

--url: specify the root directory of the repository, default is '/'.

--server-id: specify the server id configured in maven for repository authorization.

5.deploy

```shell
mvn clean deploy
```

