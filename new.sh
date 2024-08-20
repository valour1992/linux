#!/bin/bash

# Function to validate the existence of a namespace
validate_namespace() {
  namespace="$1"
  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    echo "Namespace: $namespace does not exist."
    return 1
  fi
  return 0
}

# Function to list deployments across multiple namespaces
list_deployments() {
  namespaces=("$@")
  index=1
  deployment_found=false

  for ns in "${namespaces[@]}"; do
    # Validate namespace existence
    if ! validate_namespace "$ns"; then
      continue
    fi

    echo "Namespace: $ns"
    deployments=$(kubectl get deployments -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

    # Process each deployment
    while IFS= read -r deployment; do
      if [ -n "$deployment" ]; then
        deployment_found=true
        echo "[$index] $deployment (Namespace: $ns)"
        echo "$index $deployment $ns" >> /tmp/deployment_list.txt
        index=$((index + 1))
      fi
    done <<< "$deployments"

    # If no deployments found in this namespace
    if [ "$deployment_found" = false ]; then
      echo "No deployments found in namespace: $ns"
    fi
  done

  # If no deployments found at all, notify the user
  if [ "$index" -eq 1 ]; then
    echo "No deployments found in the provided namespaces."
    return 1
  fi

  return 0
}

# Function to restart the selected deployment
restart_deployment() {
  selected_index="$1"
  selected_entry=$(grep "^$selected_index " /tmp/deployment_list.txt)
  selected_deployment=$(echo "$selected_entry" | awk '{print $2}')
  selected_namespace=$(echo "$selected_entry" | awk '{print $3}')

  echo "Restarting deployment: $selected_deployment in namespace: $selected_namespace"
  kubectl rollout restart deployment "$selected_deployment" -n "$selected_namespace"
}

# Function to restart all deployments in given namespaces
restart_all_deployments() {
  namespaces=("$@")

  for namespace in "${namespaces[@]}"; do
    # Validate namespace existence
    if ! validate_namespace "$namespace"; then
      continue
    fi

    deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
    
    if [ -z "$deployments" ]; then
      echo "No deployments found in namespace: $namespace"
      continue
    fi

    echo "Restarting all deployments in namespace: $namespace"
    for deployment in $deployments; do
      echo "Restarting deployment: $deployment"
      kubectl rollout restart deployment "$deployment" -n "$namespace"
    done
  done
}

# Main script
echo "Choose an option:"
echo "1) List and restart a specific deployment"
echo "2) Restart all deployments in specific namespaces"

# Use the correct syntax for the read command
read -p "Enter your choice: " choice

case $choice in
  1)
    # List deployments and select one to restart
    if [ "$#" -lt 1 ]; then
      echo "Usage: $0 <namespace1> <namespace2> ... <namespaceN>"
      exit 1
    fi
    list_deployments "$@"
    if [ $? -ne 0 ]; then
      exit 1
    fi
    read -p "Enter the index number of the deployment to restart: " selected_index
    if grep -q "^$selected_index " /tmp/deployment_list.txt; then
      restart_deployment "$selected_index"
    else
      echo "Invalid index. Please enter a valid number."
      exit 1
    fi
    ;;
  2)
    # Restart all deployments in specific namespaces
    if [ "$#" -lt 1 ]; then
      echo "Usage: $0 <namespace1> <namespace2> ... <namespaceN>"
      exit 1
    fi
    restart_all_deployments "$@"
    ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac

# Clean up
rm -f /tmp/deployment_list.txt
