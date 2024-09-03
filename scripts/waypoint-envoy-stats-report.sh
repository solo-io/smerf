#!/bin/bash

# Check if file_name argument is provided
if [ -z "$1" ]; then
    echo "Error: file_name argument is required"
    exit 1
fi

# The file_name is the first argument
file_name=$1

echo "Running waypoint envoy stats report..."

# Get current date
current_date=$(date +"%m-%d-%Y")

# Output directory
output_dir="out/$current_date"
output_file="$output_dir/$file_name-waypoint-envoy-stats.md"

# Create the output directory if it does not exist
mkdir -p "$output_dir"

# Get all namespaces
namespaces=$(kubectl get namespaces -o jsonpath="{.items[*].metadata.name}")

# Loop through each namespace
for namespace in $namespaces; do
    # Get the list of waypoint pods in the namespace
    wp_pods=$(kubectl get pods -n $namespace -l gateway.networking.k8s.io/gateway-name=waypoint -o jsonpath="{.items[*].metadata.name}")
    
    for wp_pod in $wp_pods; do
        # Dump the envoy stats from the `istio-proxy` container
        wpstats=$(kubectl exec -n $namespace "$wp_pod" -c istio-proxy -- pilot-agent request GET stats)

        waypoint_output_file="$output_dir/$file_name-waypoint-envoy-stats-$wp_pod.md"

        # Clear the output file if it exists
        > "$waypoint_output_file"
        # Write the envoy stats to the output file
        echo "$wpstats" >> "$waypoint_output_file"

        echo "Envoy stats for $wp_pod written to $waypoint_output_file"
    done
done

echo "Envoy stats all written"
