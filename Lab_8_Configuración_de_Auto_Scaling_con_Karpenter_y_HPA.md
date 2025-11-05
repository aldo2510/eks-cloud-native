# Laboratorio 8 - Configuración de Auto Scaling con Karpenter y HPA



## 1. Introducción

Karpenter es una solución avanzada de Auto Scaling que facilita la provisión y el escalado de nodos en función de las necesidades reales de las aplicaciones. Al integrarse de manera nativa con Amazon EKS y trabajar junto con HPA, Karpenter permite un aprovisionamiento rápido y eficiente de nodos mientras HPA escala los pods según el uso de CPU y memoria. Esta combinación optimiza el rendimiento y los costos al responder en tiempo real a la demanda de carga de trabajo, seleccionando automáticamente los tipos de instancias más adecuados y ajustando su capacidad según las especificaciones de la aplicación.


**Objetivos de Aprendizaje:**

-	Instalar y configurar Karpenter en un clúster de Amazon EKS.
-	Configurar plantillas de NodePools y recursos HPA.
-	Aprovisionar recursos dinámicamente con Karpenter y HPA.
-	Desplegar una aplicación y generar pruebas de carga.
-	Comprender el auto escalamiento con Karpenter y HPA.




## 2. Enlaces de Referencia

2.1. Escalado automático de clústeres 

```
https://docs.aws.amazon.com/es_es/eks/latest/best-practices/cluster-autoscaling.html
```

2.2. Karpenter

```
https://docs.aws.amazon.com/es_es/eks/latest/best-practices/karpenter.html
```


2.3. Empezando con Karpenter

```
https://karpenter.sh/v0.37/getting-started/getting-started-with-karpenter
```


2.4. Migración desde Cluster Autoscaler

```
https://karpenter.sh/v0.37/getting-started/migrating-from-cas/
```


2.5.	Despliegue de Pods con HPA

```
https://docs.aws.amazon.com/eks/latest/userguide/horizontal-pod-autoscaler.html
```


## 3. Instalación y Despliegue de Karpenter

3.1. Ingresamos al nodo Bastión y primeramente instalamos las métricas en el clúster. **Si ya tenemos instalado el complemento Metrics-Server, no es necesario ejecutar este paso.**

```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```


3.2. Verificamos que el deployment **metrics-server** esté ejecutándose y validamos que el servicio funcione correctamente.

```
kubectl -n kube-system get deploy
```
```
kubectl top nodes
```

3.3. A continuación, empezamos a exportar las variables de entorno para la instalación y despliegue de Karpenter. Tener en cuenta, que se deben asignar los valores de acuerdo a sus especificaciones.

```
KARPENTER_NAMESPACE=kube-system
```
```
CLUSTER_NAME=<your_cluster_name>
```


3.4. (Si no se ha hecho antes), creamos un proveedor de identidad IAM OIDC para el clúster.

```
eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve
```


3.5. Seguidamente, exportamos las otras variables para la configuración del clúster.

```
AWS_PARTITION="aws"
```
```
AWS_REGION="$(aws configure list | grep region | tr -s " " | cut -d" " -f3)"
```
```
OIDC_ENDPOINT="$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
    --query "cluster.identity.oidc.issuer" --output text)"
```
```
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' \
    --output text)
```
```
K8S_VERSION=1.32
```
```
KARPENTER_VERSION="1.3.2"
```


3.6. A continuación, creamos el rol IAM **KarpenterNodeRole**, este rol se asigna a los nodos provisionados por Karpenter y otorga los permisos necesarios para que estos interactúen con otros servicios de AWS.

```
echo '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}' > node-trust-policy.json
```
```
aws iam create-role --role-name "KarpenterNodeRole-${CLUSTER_NAME}" \
    --assume-role-policy-document file://node-trust-policy.json
```


3.7. Ahora adjuntamos las políticas requeridas al rol creado anteriormente.

```
aws iam attach-role-policy --role-name "KarpenterNodeRole-${CLUSTER_NAME}" \
    --policy-arn "arn:${AWS_PARTITION}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
```
```
aws iam attach-role-policy --role-name "KarpenterNodeRole-${CLUSTER_NAME}" \
    --policy-arn "arn:${AWS_PARTITION}:iam::aws:policy/AmazonEKS_CNI_Policy"
```
```
aws iam attach-role-policy --role-name "KarpenterNodeRole-${CLUSTER_NAME}" \
    --policy-arn "arn:${AWS_PARTITION}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
```
```
aws iam attach-role-policy --role-name "KarpenterNodeRole-${CLUSTER_NAME}" \
    --policy-arn "arn:${AWS_PARTITION}:iam::aws:policy/AmazonSSMManagedInstanceCore"
```


3.8. A continuación, creamos el rol IAM **KarpenterControllerRole**, este rol se asigna al pod controlador de Karpenter que se ejecuta dentro del clúster de EKS y permite al controlador realizar acciones administrativas en nombre del clúster, como proporcionar permisos para lanzar y terminar instancias según las necesidades de la carga de trabajo.

```
cat << EOF > controller-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ENDPOINT#*//}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_ENDPOINT#*//}:aud": "sts.amazonaws.com",
                    "${OIDC_ENDPOINT#*//}:sub": "system:serviceaccount:${KARPENTER_NAMESPACE}:karpenter"
                }
            }
        }
    ]
}
EOF
```
```
aws iam create-role --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
    --assume-role-policy-document file://controller-trust-policy.json
```
```
cat << EOF > controller-policy.json
{
    "Statement": [
        {
            "Action": [
                "ssm:GetParameter",
                "ec2:DescribeImages",
                "ec2:RunInstances",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeLaunchTemplates",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeInstanceTypeOfferings",
                "ec2:DeleteLaunchTemplate",
                "ec2:CreateTags",
                "ec2:CreateLaunchTemplate",
                "ec2:CreateFleet",
                "ec2:DescribeSpotPriceHistory",
                "pricing:GetProducts"
            ],
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "Karpenter"
        },
        {
            "Action": "ec2:TerminateInstances",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/karpenter.sh/nodepool": "*"
                }
            },
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "ConditionalEC2Termination"
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}",
            "Sid": "PassNodeIAMRole"
        },
        {
            "Effect": "Allow",
            "Action": "eks:DescribeCluster",
            "Resource": "arn:${AWS_PARTITION}:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}",
            "Sid": "EKSClusterEndpointLookup"
        },
        {
            "Sid": "AllowScopedInstanceProfileCreationActions",
            "Effect": "Allow",
            "Resource": "*",
            "Action": [
            "iam:CreateInstanceProfile"
            ],
            "Condition": {
            "StringEquals": {
                "aws:RequestTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
                "aws:RequestTag/topology.kubernetes.io/region": "${AWS_REGION}"
            },
            "StringLike": {
                "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
            }
            }
        },
        {
            "Sid": "AllowScopedInstanceProfileTagActions",
            "Effect": "Allow",
            "Resource": "*",
            "Action": [
            "iam:TagInstanceProfile"
            ],
            "Condition": {
            "StringEquals": {
                "aws:ResourceTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
                "aws:ResourceTag/topology.kubernetes.io/region": "${AWS_REGION}",
                "aws:RequestTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
                "aws:RequestTag/topology.kubernetes.io/region": "${AWS_REGION}"
            },
            "StringLike": {
                "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*",
                "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
            }
            }
        },
        {
            "Sid": "AllowScopedInstanceProfileActions",
            "Effect": "Allow",
            "Resource": "*",
            "Action": [
            "iam:AddRoleToInstanceProfile",
            "iam:RemoveRoleFromInstanceProfile",
            "iam:DeleteInstanceProfile"
            ],
            "Condition": {
            "StringEquals": {
                "aws:ResourceTag/kubernetes.io/cluster/${CLUSTER_NAME}": "owned",
                "aws:ResourceTag/topology.kubernetes.io/region": "${AWS_REGION}"
            },
            "StringLike": {
                "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*"
            }
            }
        },
        {
            "Sid": "AllowInstanceProfileReadActions",
            "Effect": "Allow",
            "Resource": "*",
            "Action": "iam:GetInstanceProfile"
        }
    ],
    "Version": "2012-10-17"
}
EOF
```
```
aws iam put-role-policy --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
    --policy-name "KarpenterControllerPolicy-${CLUSTER_NAME}" \
    --policy-document file://controller-policy.json
```


3.9. Seguidamente, añadimos las etiquetas a las subredes del nodegroup para que Karpenter sepa qué subredes utilizar.

```
for NODEGROUP in $(aws eks list-nodegroups --cluster-name "${CLUSTER_NAME}" --query 'nodegroups' --output text); do
    aws ec2 create-tags \
        --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" \
        --resources $(aws eks describe-nodegroup --cluster-name "${CLUSTER_NAME}" \
        --nodegroup-name "${NODEGROUP}" --query 'nodegroup.subnets' --output text )
done
```


3.10. Adicionalmente, añadimos las etiquetas necesarias a los Security Groups.

```
NODEGROUP=$(aws eks list-nodegroups --cluster-name "${CLUSTER_NAME}" \
    --query 'nodegroups[0]' --output text)
```
```
SECURITY_GROUPS=$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
```
```
aws ec2 create-tags \
    --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" \
    --resources "${SECURITY_GROUPS}"
```


3.11. A continuación, necesitamos permitir que los nodos que están usando el rol IAM que acabamos de crear se unan al clúster. Para ello modificamos el ConfigMap **aws-auth** en el clúster.

```
kubectl edit configmap aws-auth -n kube-system
```

3.12. Agregamos una nueva sección a la **mapRoles** con el siguiente contenido. Sustituimos la variable ${AWS_PARTITION} por la partición de la cuenta, la variable ${AWS_ACCOUNT_ID} por el ID de su cuenta y la variable ${CLUSTER_NAME} por el nombre del clúster, **pero no sustituya el** {{EC2PrivateDNSName}}.

```
- groups:
  - system:bootstrappers
  - system:nodes
  rolearn: arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}
  username: system:node:{{EC2PrivateDNSName}}

```


3.13. Generamos el archivo **karpenter.yaml** para el despliegue de Karpenter desde su Helm chart.

```
helm template karpenter oci://public.ecr.aws/karpenter/karpenter --version "${KARPENTER_VERSION}" --namespace "${KARPENTER_NAMESPACE}" \
    --set "settings.clusterName=${CLUSTER_NAME}" \
    --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}" \
    --set controller.resources.requests.cpu=1 \
    --set controller.resources.requests.memory=1Gi \
    --set controller.resources.limits.cpu=1 \
    --set controller.resources.limits.memory=1Gi > karpenter.yaml
```


3.14. Editamos el archivo **karpenter.yaml** generado en el paso anterior y modificamos la sección **affinity > nodeAffinity** para que Karpenter se ejecute en uno de los nodos del **nodegroup** existente. Para ello, agregamos un nuevo **key-value** y modificamos la variable $NODEGROUP, por el nombre del nodegroup correspondiente de nuestro clúster.

```
vim karpenter.yaml
```
```
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: karpenter.sh/nodepool
          operator: DoesNotExist
        - key: eks.amazonaws.com/nodegroup
          operator: In
          values:
          - ${NODEGROUP}
```


3.15. Ahora que el deployment está configurado, creamos el **CRD NodePool**, y otros recursos de Karpenter. Finalmente, desplegamos Karpenter ejecutando el archivo **karpenter.yaml**.

```
kubectl create -f \
    https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodepools.yaml
```
```
kubectl create -f \
    https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml
```
```
kubectl create -f \
    https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodeclaims.yaml
```
```
kubectl apply -f karpenter.yaml
```

3.16. Verificamos que los pods de Karpenter se estén ejecutando correctamente en el clúster.

```
kubectl -n kube-system get pods | grep karpenter
```



## 4. Creación de NodePool y Despliegue de Aplicación

4.1. Empezamos creando el recurso **NodePool** con las políticas de aprovisionamiento y consolidación de nodos en el clúster.

```
vim nodepool.yaml
```
```
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: nodepool-karpenter
spec:
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 0s
  limits:
    cpu: 1000
  template:
    metadata:
      labels:
        app: karpenter-lab
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: ec2nodeclass-karpenter
      requirements:
      - key: karpenter.k8s.aws/instance-generation
        operator: Gt
        values: ["3"]
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: ["c", "m"]
      - key: karpenter.k8s.aws/instance-cpu
        operator: Lt
        values: ["4"]
      - key: kubernetes.io/arch
        operator: In
        values: ["amd64"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"]
      - key: kubernetes.io/os
        operator: In
        values: ["linux"]
      expireAfter: Never
```
```
kubectl apply -f nodepool.yaml
```


4.2. Seguidamente, creamos el recurso **EC2NodeClass**, este recurso define la configuración específica que Karpenter utilizará para aprovisionar instancias EC2 que formarán parte del clúster. La variable $CLUSTER_NAME debemos modificar por el nombre de nuestro clúster.

```
vim ec2nodeclass.yaml
```
```
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: ec2nodeclass-karpenter
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  role: "KarpenterNodeRole-$CLUSTER_NAME"
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: $CLUSTER_NAME
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: $CLUSTER_NAME
  tags:
    eks: $CLUSTER_NAME
    app: karpenter-lab

```
```
kubectl apply -f ec2nodeclass.yaml
```


4.3. Verificamos que los recursos **NodePool** y **EC2NodeClass** se hayan creado correctamente y estén en **True**.

```
kubectl get nodepool,ec2nodeclasses
```


4.4. A continuación, creamos el Deployment y Service de la aplicación para realizar las pruebas de auto-scaling con Karpenter. Por el momento dejamos en **0 réplicas**. 

```
vim app-deploy.yaml
```
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-karpenter
spec:
  selector:
    matchLabels:
      run: karpenter-lab
  template:
    metadata:
      labels:
        run: karpenter-lab
    spec:
      nodeSelector:
        app: karpenter-lab
      containers:
      - name: inflated
        image: registry.k8s.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: 500m
            memory: 1Gi
          requests:
            cpu: 200m
            memory: 500Mi
---
apiVersion: v1
kind: Service
metadata:
  name: svc-karpenter
  labels:
    run: svc-karpenter
spec:
  ports:
  - port: 80
  selector:
    run: karpenter-lab
```
```
kubectl apply -f app-deploy.yaml
```


4.5.	Creamos el recurso **Horizontal Pod Autoscaling (HPA)** para el escalado automático del Deployment en base al uso del **CPU**.

```
vim hpa-karpenter.yaml
```
```
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app-karpenter
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```
```
kubectl apply -f hpa-karpenter.yaml
```

4.6.	Verificamos que el Deployment y el HPA se hayan creado correctamente.

```
kubectl get deploy,hpa
```


## 5. Pruebas de Auto Scaling y Consolidación

5.1.	Instalamos la herramienta **EKS Node Viewer** que sirve para visualizar con más detalle y analizar el estado de los nodos en un clúster de Amazon EKS.

```
wget -O eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/v0.7.1/eks-node-viewer_Linux_x86_64
```
```
chmod +x eks-node-viewer
```
```
sudo mv -v eks-node-viewer /usr/local/bin
```
```
TERM=xterm-256color
```


5.2.	Inmediatamente después de haber creado el Deployment, observamos que Karpenter ya aprovisionó un nuevo nodo. Utilizamos la herramienta **EKS Node Viewer**.

```
eks-node-viewer
```


5.3.	A continuación, abrimos una nueva terminal y generamos carga a la aplicación para que **HPA** realice el auto escalado a nivel de **Pods** y **Karpenter** el auto escalado a nivel de **Nodos**.

```
kubectl run -i \
    --tty load-generator \
    --rm --image=busybox \
    --restart=Never \
    -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://svc-karpenter; done"
```

5.4.	Esperamos unos 10 segundos, y ahora observamos que el porcentaje de uso de CPU de la aplicación se eleva. Por lo que, **HPA** empieza a escalar los **Pods**. Asimismo, **Karpenter** también empieza a escalar los **Nodos** para que las réplicas se puedan ejecutar correctamente.

```
kubectl get hpa -w
```
```
eks-node-viewer
```

5.7.	Asimismo, si ahora escalamos las réplicas del Deployment a **0**, Karpenter retira todos los nodos adicionales automáticamente.

```
kubectl scale deploy app-karpenter --replicas=0
```


5.8.	A su vez, podemos indicar para que Karpenter pueda lanzar instancias **Spot** con el fin de optimizar aún más los costos. Modificamos el archivo **nodepool.yaml** y agregamos en los **values** el tipo de capacidad como **spot**. En la siguiente imagen observamos como quedaría.

```
vi nodepool.yaml
```

5.9.	Finalmente, limpiamos los recursos creados.

```
kubectl delete -f app-deploy.yaml
```
```
kubectl delete -f hpa-karpenter.yaml
```
```
kubectl delete -f nodepool.yaml
```
```
kubectl delete -f ec2nodeclass.yaml
```
```
kubectl delete -f karpenter.yaml
```
```
kubectl delete -f \
    https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodepools.yaml
```
```
kubectl delete -f \
    https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml
```
```
kubectl delete -f \
    https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/pkg/apis/crds/karpenter.sh_nodeclaims.yaml
```



## 6. Resumen

En este laboratorio, hemos aprendido a desplegar y configurar Karpenter en un clúster de Amazon EKS para habilitar el auto escalado dinámico de Nodos en conjunto con HPA para la gestión de Pods. Se definieron plantillas de NodePools y configuraciones de HPA para aprovisionar recursos de manera eficiente según la demanda. Luego, se desplegó una aplicación y se realizaron pruebas de carga para analizar el comportamiento del escalado. Finalmente, se evaluó la interacción entre Karpenter y HPA, demostrando cómo ambos optimizan el uso de recursos y mejoran la capacidad de respuesta del clúster.