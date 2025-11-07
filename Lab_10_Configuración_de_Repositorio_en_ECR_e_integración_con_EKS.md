# Laboratorio 10 - Configuración de Repositorio en ECR e integración con EKS



## 1. Introducción

Amazon Elastic Container Registry (ECR) es un servicio de almacenamiento de contenedores administrado que facilita la gestión y el despliegue de imágenes en aplicaciones. ECR elimina la necesidad de operar y escalar infraestructura, proporcionando una solución segura, integrada y altamente disponible para almacenar y compartir imágenes entre servicios de AWS y usuarios autorizados.

**Objetivos de Aprendizaje:**

-	Instalar Docker y crear un Dockerfile personalizado.
-	Empaquetar una aplicación en una imagen de contenedor.
-	Creación y configuración de un repositorio en Amazon ECR.
-	Autenticación de Docker con Amazon ECR y push de imágenes a los repositorios.
-	Despliegue de imágenes desde ECR a un clúster de Amazon EKS.


## 2. Enlaces de Referencia

2.1. Creación de un repositorio ECR privado

```
https://docs.aws.amazon.com/es_es/AmazonECR/latest/userguide/repository-create.html
```

2.2. Políticas de repositorios privados en Amazon ECR

```
https://docs.aws.amazon.com/es_es/AmazonECR/latest/userguide/repository-policies.html
```

2.3. Insertar una imagen a un repositorio ECR privado

```
https://docs.aws.amazon.com/es_es/AmazonECR/latest/userguide/image-push.html
```

2.4. Uso de imágenes de Amazon ECR con Amazon EKS

```
https://docs.aws.amazon.com/es_es/AmazonECR/latest/userguide/ECR_on_EKS.html
```


## 3. Instalación de Docker y Creación de Imagen
3.1. Ingresamos al nodo Bastion y actualizamos la caché de paquetes.

```
sudo yum update -y
```

3.2. Instalamos el paquete de Community Edition de Docker más reciente.

```
sudo yum install docker
```


3.3. Iniciamos el servicio de Docker y validamos que se esté ejecutando correctamente.

```
sudo systemctl start docker
```
```
sudo systemctl status docker
```

3.4. Agregamos al usuario **ec2-user** al grupo **docker** para que pueda ejecutar los comandos de Docker sin usar **sudo**.

```
sudo usermod -a -G docker ec2-user
```

3.5. Cerramos sesión de la terminal SSH actual y volvemos a conectarnos a la instancia. De esta forma, la nueva sesión SSH tendrá los permisos de grupo de **docker** adecuados. **En algunos casos**, es posible que tenga que reiniciar la instancia para que el **ec2-user** tenga los permisos necesarios.


3.6. Seguidamente, comprobamos que el **ec2-user** pueda ejecutar los comandos de **Docker** sin **sudo**.

```
docker info
```

3.7. Ahora creamos una imagen de Docker de una aplicación web. Para ello, creamos un archivo denominado **Dockerfile**. El siguiente DockerFile utiliza la imagen pública de Amazon Linux 2 alojada en Amazon ECR Public con la instrucción **FROM**. Las instrucciones **RUN** actualizan la caché del paquete, instalan los paquetes de software para el servidor web y escriben el contenido **“Hello World”** en la raíz de documentos del servidor web. La instrucción **EXPOSE** significa que el **puerto 80** del contenedor es el que está escuchando y la instrucción **CMD** inicia el servidor web.

```
vim Dockerfile
```

```
FROM public.ecr.aws/amazonlinux/amazonlinux:latest

# Update installed packages and install Apache
RUN yum update -y && \
 yum install -y httpd

# Write hello world message
RUN echo 'Hello World!' > /var/www/html/index.html

# Configure Apache
RUN echo 'mkdir -p /var/run/httpd' >> /root/run_apache.sh && \
 echo 'mkdir -p /var/lock/httpd' >> /root/run_apache.sh && \
 echo '/usr/sbin/httpd -D FOREGROUND' >> /root/run_apache.sh && \
 chmod 755 /root/run_apache.sh

EXPOSE 80

CMD /root/run_apache.sh
```

3.8. Creamos la imagen Docker denominado **hello-world** desde el **Dockerfile**. **En algunas versiones de Docker** pueden requerir la ruta completa de su Dockerfile en lugar de la ruta relativa que se muestra en el siguiente comando.

```
docker build -t hello-world .
```

3.9. Verificamos que la imagen se haya creado correctamente.

```
docker images
```


## 4. Creación de Repositorio y envío de Imagen a Amazon ECR

4.1. Ingresamos a la consola de AWS, en la barra superior de búsqueda escribimos **ecr** y **seleccionamos el servicio** para acceder.


4.2. Clic en **Create** para crear un nuevo repositorio en Amazon ECR.


4.3. Asignamos un **nombre al repositorio privado**, dejamos las otras opciones por defecto y le damos **clic en Create**.


4.4. Seleccionamos el **repositorio creado** y le damos clic en la opción **View push commands**. 


4.5. A continuación, encontraremos las instrucciones para subir imágenes de contenedores a nuestro repositorio de Amazon ECR.


4.6. En base a las instrucciones anteriores. Ingresamos nuevamente a la terminal del nodo Bastión y recuperamos el token de autenticación para acceder al Registry, como se indica en la **instrucción 1**.

```
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 730335437082.dkr.ecr.us-west-2.amazonaws.com
```


4.7. A continuación, etiquetamos la imagen **hello-world** construida anteriormente para subir al repositorio de ECR, **como se indica en la instrucción 3** **(la instrucción 2 lo omitimos, ya que previamente se ha construido una imagen)**.

```
docker tag hello-world:latest 730335437082.dkr.ecr.us-west-2.amazonaws.com/repo-lab:latest
```

4.8. Seguidamente, subimos la imagen al repositorio creado en Amazon ECR.

```
docker push 730335437082.dkr.ecr.us-west-2.amazonaws.com/repo-lab:latest
```

4.9. En la consola de AWS verificamos que la imagen se haya subido correctamente. Para ello, le damos **clic en el nombre del repositorio** para visualizar todas las imágenes.


4.10. Asimismo, le damos clic en **Copy URI** para obtener la dirección de la imagen y llevarla a un despliegue en Amazon EKS.


## 5. Uso de Imágenes de Amazon ECR con Amazon EKS 

5.1. Desplegamos una aplicación que haga el llamado a la imagen subida en Amazon ECR. Para ello en el parámetro **'image'** del siguiente manifiesto colocamos la dirección de la imagen copiada en el paso anterior.

```
vim app-ecr.yaml
```
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-ecr
  labels:
    app: app-ecr
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pod-ecr
  template:
    metadata:
      labels:
        app: pod-ecr
    spec:
      containers:
      - name: hello-world
        image: 730335437082.dkr.ecr.us-west-2.amazonaws.com/repo-lab:latest
        ports:
        - containerPort: 80
```
```
kubectl apply -f app-ecr.yaml
```

5.2. Verificamos que los Pods se estén ejecutando correctamente.

```
kubectl get pods
```

5.3. Seguidamente, exponemos internamente la aplicación a través de un recurso **Service** denominado **app-ecr-svc** y verificamos que se haya creado correctamente.

```
kubectl expose deploy app-ecr --name=app-ecr-svc --port=80
```
```
kubectl get svc,ep app-ecr-svc
```

5.4. Finalmente, creamos un Pod de pruebas denominado **tmp** para validar que la aplicación responde con el mensaje de **'Hello World!'** configurado inicialmente en el **Dockerfile**.

```
kubectl run tmp --restart=Never --rm -i --image=nginx:alpine -- curl -v app-ecr-svc
```


## 6. Resumen 

En este Laboratorio se instaló Docker y se creó un Dockerfile personalizado para empaquetar una aplicación en una imagen de contenedor. Asimismo, se configuró un repositorio privado en Amazon ECR, donde se autenticó Docker para realizar el Push de la imagen a este repositorio. Finalmente, la imagen fue desplegada en un clúster de Amazon EKS, demostrando el flujo completo desde la creación de la imagen hasta su despliegue en un entorno administrado de EKS.







