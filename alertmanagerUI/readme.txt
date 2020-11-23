
Pre-req:
	1. place the script and two .txt file in same folder 
	2. Make sure that the .txt files does have only one line

Implementations Step:

Run below command 
sh deployAlertManagerUI.sh --subscription <subscription id> --resource-group <cluster resource group name> --cluster-name <cluster name>

If successful run 
	rm -r *.json *.yaml



Reversion should be done manually 


Failure cases
1. Alertmanager didn't start 
	--> proceed manual steps
2. prometheus didn't start
	--> proceed manual steps

