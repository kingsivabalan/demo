# scripts to deploy alertmanager UI

set -eu -o pipefail

# get arguments from script

usage(){

        echo "
        DESCRIPTION
                Deploy/rever the alertmanager UI in monitoring solution

        SYNOPSIS
                $0 --subscription <subscription id> --resource-group <cluster resource group name> --cluster-name <cluster name>
                $0 -s <subscription id> -g  <cluster resource group name> -n  <cluster name>

        ARGUMENTS
                --subscription , -s    - subscriptin id
                --resource-group , -g  - resource group name
                --cluster-name, -n     - cluster name
        " >&2
        exit 1
}



main(){

echo "Starting script"
while [[ "$#" -gt 0 ]]; do
        case "${1:-}" in
        -h|--help)
                usage
                ;;

        -s|--subscription)
                subscription="${2:-}"
                ;;

        -g|--resource-group)
                rg="${2:-}"
                ;;

        -n|--custer-name)
                clustername="${2:-}"
                ;;
        esac
        shift
done

# checking the required input variables
if [[ -z "${subscription:-}" || -z  "${rg:-}" || -z "${clustername:-}" ]]; then echo "one of the mandatory field is missing. Please check";usage; fi


# download and set kubeconfig
az account set -s ${subscription}
az account show -o tsv --query name
rm -r kubeconfig-admin.yaml &2>/dev/null
az aks get-credentials -n ${clustername} -g ${rg} -a -f kubeconfig-admin.yaml
export KUBECONFIG=$(pwd)/kubeconfig-admin.yaml



# change alert rule

kubectl get prometheusrules -n monitoring prometheus-kube-state-metrics-rules -o json >prometheus-kube-state-metrics-rules.json

# chaning alert rule 1
key=$(jq '.spec.groups[].rules|to_entries[]|select(.value.alert=="DeploymentGenerationMismatch")|.key' prometheus-kube-state-metrics-rules.json)
query=$(cat DeploymentGenerationMismatch.txt)
jq --argjson key $key --arg query "$query" '.spec.groups[].rules[$key].expr|=$query' prometheus-kube-state-metrics-rules.json >new-rules-temp.json

# changing alert rule 2
key=$(jq '.spec.groups[].rules|to_entries[]|select(.value.alert=="DeploymentReplicasNotUpdated")|.key' new-rules-temp.json)
query=$(cat DeploymentReplicasNotUpdated.txt)
jq --argjson key $key --arg query "$query" '.spec.groups[].rules[$key].expr|=$query' new-rules-temp.json >new-rules.json

rm -r prometheus-kube-state-metrics-rules.json
rm -r new-rules-temp.json

kubectl apply -f new-rules.json


# expose UI
echo "modifying alertmanager"
kubectl get alertmanager -n monitoring -o yaml >alertmanager.yaml
yq w -i alertmanager.yaml 'items[*].spec.routePrefix' /alertmanager
kubectl apply -f alertmanager.yaml

sleep 10s

count=0
status=$(kubectl get pods -n monitoring alertmanager-prometheus-operator-alertmanager-0 -o jsonpath={.status.phase})
while [[ ("$status" != "Running") && ("$count" -lt 6) ]]; do
        sleep 10s
        status=$(kubectl get pods -n monitoring alertmanager-prometheus-operator-alertmanager-0 -o jsonpath={.status.phase})
        echo "checking status of alertmanager - $status"
        count=$((count+1))
done
if [ "$status" != "Running" ]; then echo "Alert manager pod status - $status"; exit 1  ; fi

count=0
containerCount=$(kubectl get pods -n monitoring alertmanager-prometheus-operator-alertmanager-0 -o jsonpath={.status.containerStatuses[*].ready}| tr [:space:] '\n' | grep -i -c true)
while [[ ("$containerCount" -ne 2 ) && ("$count" -lt 6) ]]; do
        sleep 10s
        containerCount=$(kubectl get pods -n monitoring alertmanager-prometheus-operator-alertmanager-0 -o jsonpath={.status.containerStatuses[*].ready}| tr [:space:] '\n' | grep -i -c true)
        echo "checking alertmanager container ready count - $containerCount"
        count=$((count+1))
done

if [[ "$containerCount" -ne 2 ]]; then echo "Alert manager pod container count - $containerCount"; exit 1  ; fi
echo "Alertmanager path - $(kubectl get pods -n monitoring alertmanager-prometheus-operator-alertmanager-0 -o jsonpath='{.spec.containers[0].args[6]}')"


kubectl get ing kube-prometheus -n monitoring -o yaml >kube-prometheus.yaml
yq w -i kube-prometheus.yaml 'spec.rules[0].http.paths[1].path' /alertmanager
yq w -i kube-prometheus.yaml 'spec.rules[0].http.paths[1].backend.serviceName' prometheus-operator-alertmanager
yq w -i kube-prometheus.yaml 'spec.rules[0].http.paths[1].backend.servicePort' 9093
kubectl apply -f kube-prometheus.yaml

echo "Modifying prometheus"

kubectl get prometheus kube-prometheus -n monitoring -o yaml >prometheus.yaml
yq w -i prometheus.yaml 'spec.alerting.alertmanagers[*].pathPrefix' /alertmanager
kubectl apply -f prometheus.yaml

echo "Prometheus path - $(kubectl get prometheus kube-prometheus -n monitoring -o jsonpath='{.spec.alerting.alertmanagers[].pathPrefix}')"
echo "Prometheus pod current status - $(kubectl get pods prometheus-kube-prometheus-0 -n monitoring -o wide)"
echo "deleting prometheus pod"

kubectl delete pod prometheus-kube-prometheus-0 -n monitoring
count=0
status=$(kubectl get pods -n monitoring prometheus-kube-prometheus-0 -o jsonpath={.status.phase})
while [[ ("$status" != "Running") && ("$count" -lt 6) ]]; do
        sleep 10s
        status=$(kubectl get pods -n monitoring prometheus-kube-prometheus-0 -o jsonpath={.status.phase})
        echo "checking status of prometheus - $status"
        count=$((count+1))
done
if [ "$status" != "Running" ]; then echo "Prometheus pod status - $status"; exit 1  ; fi

count=0
containerCount=$(kubectl get pods -n monitoring prometheus-kube-prometheus-0 -o jsonpath={.status.containerStatuses[*].ready}| tr [:space:] '\n' | grep -i -c true)
while [[ ("$containerCount" -ne 4 ) && ("$count" -lt 12) ]]; do
        sleep 10s
        containerCount=$(kubectl get pods -n monitoring prometheus-kube-prometheus-0 -o jsonpath={.status.containerStatuses[*].ready}| tr [:space:] '\n' | grep -i -c true)
        echo "checking container ready count - $containerCount"
        count=$((count+1))
done

if [[ "$containerCount" -ne 4 ]]; then echo "Prometheus pod container count - $containerCount"; exit 1  ; fi

echo "check the host path - $(yq r kube-prometheus.yaml 'spec.rules[0].host')/alertmanager"



}





main "$@"
