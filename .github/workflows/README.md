# Deployment Setup

## GitHub Secrets

Create one secret under **Settings > Secrets and variables > Actions > Secrets**:

| Secret | Value |
|---|---|
| `AZURE_CREDENTIALS` | JSON output from: `az ad sp create-for-rbac --name "gh-zava-deploy" --role Contributor --scopes /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-dev --json-auth` |

## GitHub Variables

Create three variables under **Settings > Secrets and variables > Actions > Variables**:

| Variable | Value |
|---|---|
| `ACR_NAME` | `cr4uz7gnv4ukkp2` |
| `APP_NAME` | `app-4uz7gnv4ukkp2` |
| `RESOURCE_GROUP` | `rg-dev` |

## ACR Push Permission

The service principal needs `AcrPush` on the container registry:

```bash
SP_ID=$(az ad sp list --display-name "gh-zava-deploy" --query "[0].id" -o tsv)
ACR_ID=$(az acr show --name cr4uz7gnv4ukkp2 --query id -o tsv)
az role assignment create --assignee "$SP_ID" --role AcrPush --scope "$ACR_ID"
```

## Trigger

The workflow runs on every push to `main` or via manual dispatch in the Actions tab.
