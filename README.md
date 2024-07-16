This script will create a resource group, vnet, subnet, delegate the subnet, and create all the other necessary components to build a CMK NetApp volume. The script will run and determine location based on the current Azure cloud you are logged into (ie. Gov vs Commercial).  By default it will use usgovvirginia in Gov and eastus in Commercial. You may need to adjust the variables at the top of the script.  From my experience this script runs without any issue in Azure Commercial but fails to create a volume in Government with the following message:

```
(InternalServerError) Error when creating - Unable to use the configured encryption key, please check if key is active
Code: InternalServerError
Message: Error when creating - Unable to use the configured encryption key, please check if key is active
Exception Details:	(ErrorFromNFSaaSErrorState) Error when creating - Unable to use the configured encryption key, please check if key is active
	Code: ErrorFromNFSaaSErrorState
	Message: Error when creating - Unable to use the configured encryption key, please check if key is active
```
