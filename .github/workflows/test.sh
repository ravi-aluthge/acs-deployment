#!/usr/bin/env bash

COMMIT_MESSAGE=$1
export GIT_DIFF=$(git diff origin/master --name-only .)
export STAGE_NAME=$GITHUB_JOB
export BRANCH_NAME=$(echo ${GITHUB_REF##*/})
export values_file=helm/alfresco-content-services/values.yaml
export namespace=$(echo ${BRANCH_NAME} | cut -c1-28 | tr /_ - | tr -d [:punct:] | awk '{print tolower($0)}')-${GITHUB_RUN_NUMBER}-${GITHUB_JOB}
export release_name_ingress=ing-${GITHUB_RUN_NUMBER}-${GITHUB_JOB}
export release_name_acs=acs-${GITHUB_RUN_NUMBER}-${GITHUB_JOB}

# pod status
pod_status() {
    kubectl get pods --namespace $namespace -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[?\(@.type==\'Ready\'\)].status
}

# failed pods logs
failed_pod_logs() {
    pod_status | grep False | awk '{print $1}' | while read pod; do echo -e '\e[1;31m' $pod '\e[0m' && kubectl logs $pod --namespace $namespace; done
}

# pods ready
pods_ready() {
    PODS_COUNTER=0
    PODS_COUNTER_MAX=60
    PODS_SLEEP_SECONDS=10

    while [ "$PODS_COUNTER" -lt "$PODS_COUNTER_MAX" ]; do
    totalpods=$(pod_status | grep -v NAME | wc -l | sed 's/ *//')
    readypodcount=$(pod_status | grep ' True' | wc -l | sed 's/ *//')
    if [ "$readypodcount" -eq "$totalpods" ]; then
            echo "     $readypodcount/$totalpods pods ready now"
            pod_status
        echo "All pods are ready!"
        break
    fi
        PODS_COUNTER=$((PODS_COUNTER + 1))
        echo "just $readypodcount/$totalpods pods ready now - sleeping $PODS_SLEEP_SECONDS seconds - counter $PODS_COUNTER"
        sleep "$PODS_SLEEP_SECONDS"
        continue
    done

    if [ "$PODS_COUNTER" -ge "$PODS_COUNTER_MAX" ]; then
    pod_status
    echo "Pods did not start - exit 1"
    failed_pod_logs
    if [[ "$COMMIT_MESSAGE" != *"[keep env]"* ]]; then
        helm delete $release_name_ingress $release_name_acs -n $namespace
        kubectl delete namespace $namespace
    fi
    exit 1
    fi
}

prepare_namespace() {
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
    name: $namespace
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
    name: $namespace:psp
    namespace: $namespace
rules:
- apiGroups:
    - policy
    resourceNames:
    - kube-system
    resources:
    - podsecuritypolicies
    verbs:
    - use
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
    name: $namespace:psp:default
    namespace: $namespace
roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: Role
    name: $namespace:psp
subjects:
- kind: ServiceAccount
    name: default
    namespace: $namespace
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
    name: $namespace:psp:$release_name_ingress-nginx-ingress
    namespace: $namespace
roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: Role
    name: $namespace:psp
subjects:
- kind: ServiceAccount
    name: $release_name_ingress-nginx-ingress
    namespace: $namespace
---
EOF
}

echo $COMMIT_MESSAGE
echo $GITHUB_JOB
echo $BRANCH_NAME
echo $values_file
echo $namespace
echo $release_name_ingress
echo $release_name_acs
echo $GIT_DIFF


#check it later
if [[ ${GITHUB_JOB} != "test" ]]; then
    values_file="helm/alfresco-content-services/${TRAVIS_BUILD_STAGE_NAME}_values.yaml"
fi

deploy=false

if [[ "${BRANCH_NAME}" == "master" ]] || [[ "${COMMIT_MESSAGE}" == *"[run all tests]"* ]] || [[ "${COMMIT_MESSAGE}" == *"[release]"* ]] || [[ "${GIT_DIFF}" == *helm/alfresco-content-services/${GITHUB_JOB}_values.yaml* ]] || [[ "${GIT_DIFF}" == *helm/alfresco-content-services/templates* ]] || [[ "${GIT_DIFF}" == *helm/alfresco-content-services/charts* ]] || [[ "${GIT_DIFF}" == *helm/alfresco-content-services/requirements* ]] || [[ "${GIT_DIFF}" == *helm/alfresco-content-services/values.yaml* ]] || [[ "${GIT_DIFF}" == *test/postman/helm* ]]
then
    deploy=true
fi

echo 'mieszko'
echo $deploy

pod_status
failed_pod_logs
pods_ready
prepare_namespace