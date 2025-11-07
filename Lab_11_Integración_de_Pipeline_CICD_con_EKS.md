# Laboratorio 11 - Integración de Pipeline CI/CD con EKS



## 1. Introducción

La integración de un Pipeline CI/CD con Amazon EKS permite automatizar el proceso de construcción, prueba y despliegue de aplicaciones en contenedores, asegurando un flujo continuo y eficiente desde el desarrollo hasta la producción. Mediante un pipeline, los cambios en el código fuente se gestionan de manera automática, integrando repositorios, herramientas de construcción y despliegue, y optimizando el rendimiento en los clústeres. Este flujo continuo asegura un despliegue rápido y confiable, optimizando tiempos y reduciendo errores manuales, mientras se refuerzan las prácticas modernas de DevOps en entornos contenerizados.


**Objetivos de Aprendizaje:**

-	Crear un repositorio en GitHub.
-	Crear un repositorio en Amazon ECR para almacenar imágenes.
-	Crear un proyecto en AWS CodeBuild para definir las fases del pipeline.
-	Configurar un rol IAM para la autenticación y despliegue en Amazon EKS.
-	Ejecutar un pipeline básico para despliegues en Amazon EKS.



## 2. Enlaces de Referencia

2.1. Creación de una cuenta en GitHub

```
https://docs.github.com/es/get-started/start-your-journey/creating-an-account-on-github
```

2.2. Creación de un repositorio en GitHub

```
https://docs.github.com/es/repositories/creating-and-managing-repositories/creating-a-new-repository
```

2.3. Administración de Tokens en GitHub

```
https://docs.github.com/es/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
```

2.4. Creación de un repositorio ECR privado

```
https://docs.aws.amazon.com/es_es/AmazonECR/latest/userguide/repository-create.html
```

2.5. Creación de un proyecto de construcción en AWS CodeBuild

```
https://docs.aws.amazon.com/es_es/codebuild/latest/userguide/create-project.html
```


## 3. Instalación de Git y clonado de Repositorio

3.1. Antes de empezar con este laboratorio, suponemos que ya ha creado un **repositorio en su cuenta de GitHub** y ya tiene un **Token de acceso** para subir archivos. Como primer paso ingresamos al nodo Bastión e instalamos el paquete de Git para realizar las operaciones posteriores.

```
sudo yum install git -y
```


3.2. Realizamos el clonado del repositorio público que usaremos para este laboratorio e ingresamos al directorio. 

```
git clone https://github.com/gsono9825/eks-CICD.git
```
```
cd eks-CICD/
```


3.3. Una vez que ya clonamos el repositorio y obtuvimos los archivos de forma local, eliminamos el repositorio de origen y agregamos nuestro repositorio personal reemplazando la variable **<URL_REPOSITORY>** por la que corresponda.

```
git remote remove origin
```
```
git remote add origin <URL_REPOSITORY>
```


3.4. Verificamos que el repositorio de origen se haya actualizado y seguidamente realizamos un **push** para subir los archivos a nuestro repositorio. Una vez que ejecutemos el push, colocamos el **Username** y el **Password** **(Token)** de nuestra cuenta para la autenticación.

```
git remote -v
```
```
git branch -M main
```
```
git push -u origin main
```


3.5. Ahora, nos dirigimos a nuestro repositorio de GitHub y observamos que los archivos se han subido correctamente.



## 4. Creación de Proyecto en CodeBuild y Roles IAM

4.1. Empezamos creando un proyecto en **AWS CodeBuild** para las etapas del **Pipeline**, para ello ingresamos al servicio de **CodeBuild**.


4.2. Clic en **Create project**.


4.3. Asignamos un nombre al proyecto.


4.4. En el apartado de **Source**, en **Source provider** seleccionamos **GitHub**. En este laboratorio trabajaremos con un repositorio público, si desea trabajar con un repositorio privado se deben configurar las credenciales o el token de acceso para autenticarse y conectarse con su cuenta de GitHub. En nuestro caso, ignoramos el mensaje de color rojo que figura.


4.5. En **Repository** seleccionamos **Public repository** y en **Repository URL pegamos la URL de nuestro repositorio público de GitHub**.


4.6. En el apartado de **Environment** nos dirigimos a **Service Role** y **creamos un nuevo Role**. A continuación, clic en **Additional configuration** para desplegar otras opciones.


4.7. En el apartado **Additional configuration**, marcamos el cuadro de **Privileged**. Esta opción permitirá a CodeBuild construir imágenes Docker con privilegios.


4.8. En el mismo apartado, en **VPC seleccionamos la VPC donde se encuentra el clúster EKS**, en **Subnets seleccionamos las subredes privadas**, y en S**ecurity groups seleccionamos el Security Group del Bastión**, ya que este tiene los permisos para conectarse con la API del clúster (también se podría crear un propio SG para el proyecto CodeBuild).


4.9. Seguidamente, nos ubicamos en el apartado de **Environments variables** para agregar las variables de entorno al pipeline que se definirá en el archivo **buildspec.yml**.


4.10. La variable **EKS_CLUSTER_NAME**, es el nombre del clúster EKS al cual realizaremos los despliegues automatizados.


4.11.	Para las variables **ECR** y **REPOSITORY**, necesitamos crear un repositorio en Amazon ECR (en el laboratorio 6 se muestran los pasos de como crear un repositorio en ECR). Una vez ya creado el repositorio, ingresamos al repo y obtenemos los datos para las variables. La variable **ECR** es solo **la URI de la cuenta del servicio ECR**, y la variable **REPOSITORY** es la **URI completa**.


4.12. Regresamos al apartado de configuración de variables en CodeBuild, definiendo momentáneamente las variables obtenidas en los pasos anteriores.


4.13.	Seguidamente, en el apartado **Buildspec**, seleccionamos la opción **Use a buildspec file** para que utilice el archivo buildspec.yml por defecto que se encuentra en la raíz de nuestro repositorio de GitHub.


4.14. Con respecto a las demás opciones lo dejamos por defecto, finalmente le damos clic en **Create build project**.


4.15.	Una vez que creado el proyecto en CodeBuild, copiamos el **arn del rol** de nuestro proyecto, esto lo usaremos para la política del rol IAM que asumirá.


4.16.	A continuación, debemos crear el **rol IAM** que tendrá acceso al clúster EKS. Este rol nos servirá para que el proyecto de CodeBuild lo asuma y pueda desplegar los cambios en el clúster. Para ello, regresamos nuevamente al servidor Bastion y ejecutamos el siguiente comando para crear la política denominada **EKSPolicyDescribe** con la acción **eks:Describe***.

```
aws iam create-policy \
    --policy-name EKSPolicyDescribe \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": "eks:Describe*",
                "Resource": "*"
            }
        ]
    }'
```

4.17.	Seguidamente, creamos el **rol IAM** denominado **EKS-CICDRole** adjuntando en la política de confianza el **arn del rol de CodeBuild que copiamos en el punto 4.15**. Esto permitirá que el rol del proyecto de CodeBuild pueda asumir el rol **EKS-CICDRole**.

```
aws iam create-role \
    --role-name EKS-CICDRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::767397771039:role/service-role/CodeBuildRole"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
```

4.18.	Cuando creamos el rol nos dará un output. Ahora copiamos el **arn del rol EKS-CICDRole** para posteriormente agregarlo a las variables del proyecto de CodeBuild.


4.19.	Seguidamente, adjuntamos la política **EKSPolicyDescribe** creada en el **punto 4.16** al rol IAM **EKS-CICDRole**.

```
aws iam attach-role-policy \
    --role-name EKS-CICDRole \
    --policy-arn arn:aws:iam::767397771039:policy/EKSPolicyDescribe
```

4.20.	Asimismo, al rol IAM **CodeBuildRole** adjuntamos la política **AmazonEC2ContainerRegistryPowerUser**, con el fin de que el proyecto de Build tenga los permisos para ejecutar las acciones en el repositorio de imágenes ECR.

```
aws iam attach-role-policy \
    --role-name CodeBuildRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```


4.21.	Regresamos a la consola de AWS, en el proyecto de CodeBuild creado le damos clic en **Edit**.


4.22.	Nos dirigimos nuevamente al apartado de **Environment variables** y **agregamos la variable EKS_ROLE_ARN**, y como **value** le asignamos el **arn del rol IAM EKS-CICDRole copiado en el punto 4.18**. Una vez agregada la variable, bajamos y le damos clic en **Update project**. 


4.23.	A continuación, ingresamos a nuestro clúster de EKS, le damos clic en **Access** y seguidamente clic en **Create access entry** para crear un nuevo acceso IAM al clúster.


4.24.	En el apartado **Configure IAM Access entry**, en **IAM principal** seleccionamos el **rol IAM EKS-CICDRole**, en **type** lo dejamos en **Standard** y le damos clic en **Next**.


4.25.	En el apartado **Add access policy**, en **Policy name** seleccionamos **AmazonEKSClusterAdminPolicy**, clic en **Add policy** y finalmente clic en **Next**.


4.26.	Finalmente, en el apartado **Review and create** le damos clic en **Create**.




## 5. Ejecución de Pipeline CI/CD y Despliegue de Aplicación

5.1. Ahora, ingresamos a nuestro proyecto en **CodeBuild** y le damos clic en **Start build** para iniciar la ejecución del pipeline.


5.2. Una vez que se inicia el pipeline podemos dar clic en **Tail logs** para ver toda la ejecución y las acciones en tiempo real.


5.3. Observamos que el pipeline finaliza correctamente ejecutando todas las acciones definidas en el archivo **buildspec.yml** ubicado en nuestro repositorio de GitHub.


5.4. A continuación, nos dirigimos a la terminal del Bastión y verificamos que el **Deployment** de la aplicación se haya realizado exitosamente.

```
kubectl get deploy
```

5.5. Seguidamente, verificamos que la aplicación web esté respondiendo internamente con el contenido definido en el código fuente. Primero obtenemos la dirección IP interna de uno de los Pods y lo copiamos.

```
kubectl get pods -owide
```

5.6. Finalmente, creamos un pod temporal para realizar las pruebas y comprobar el funcionamiento de la aplicación web.

```
kubectl run tmp --restart=Never --rm -i --image=nginx:alpine -- curl <POD_IP>
```


## 6. Resumen

En este laboratorio se integró un pipeline CI/CD con Amazon EKS para automatizar el despliegue de aplicaciones. Se clonó un repositorio público desde GitHub, se configuró un repositorio de Amazon ECR para almacenar imágenes y se creó un proyecto en CodeBuild para construir y desplegar automáticamente las aplicaciones. Finalmente, se ejecutó el pipeline, demostrando cómo los cambios en el código se reflejan en tiempo real en el clúster de EKS, optimizando el proceso de entrega continua y garantizando un despliegue eficiente y automatizado.
