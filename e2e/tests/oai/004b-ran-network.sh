#!/bin/bash
#!/usr/bin/env bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2024 The Nephio Authors.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

## TEST METADATA
## TEST-NAME: Deploy OAI CU-UP and DU Network Functions
##

set -o pipefail
set -o errexit
set -o nounset
[[ ${DEBUG:-false} != "true" ]] || set -o xtrace

# shellcheck source=e2e/defaults.env
source "$E2EDIR/defaults.env"

# shellcheck source=e2e/lib/k8s.sh
source "${LIBDIR}/k8s.sh"

# shellcheck source=e2e/lib/kpt.sh
source "${LIBDIR}/kpt.sh"

# shellcheck source=e2e/lib/porch.sh
source "${LIBDIR}/porch.sh"

function _wait_for_ran {
    kubeconfig=$1
    wait_msg=$2
    link_name=$3

    info "waiting for $link_name link to be established"
    timeout=600

    temp_file=$(mktemp)
    kubectl logs -l app.kubernetes.io/name=oai-cu-cp --tail -1 -n oai-ran-cucp -c cucp --kubeconfig "$kubeconfig" >temp_file
    while
        grep "$wait_msg" temp_file
        status=$?
        [[ $status != 0 ]]
    do
        if [[ $timeout -lt 0 ]]; then
            kubectl logs -l app.kubernetes.io/name=oai-cu-cp -n oai-ran-cucp -c cucp --kubeconfig "$kubeconfig" --tail 50
            error "Timed out waiting for $link_name link to be established"
        fi
        timeout=$((timeout - 5))
        sleep 5
        kubectl logs -l app.kubernetes.io/name=oai-cu-cp --tail -1 -n oai-ran-cucp -c cucp --kubeconfig "$kubeconfig" >temp_file
    done
    debug "timeout: $timeout"
    rm "${temp_file}"
}

_regional_kubeconfig="$(k8s_get_capi_kubeconfig "regional")"
_edge_kubeconfig="$(k8s_get_capi_kubeconfig "edge")"

k8s_apply "$TESTDIR/004b-ran-network.yaml"

for nf in du cuup; do
    k8s_wait_ready "packagevariant" "oai-$nf"
done

porch_wait_published_packagerev "oai-ran-cuup" "edge" "$REVISION"
kpt_wait_pkg "edge" "oai-ran-cuup" "nephio" "1800"
k8s_wait_exists "nfdeployment" "cuup-edge" "$_edge_kubeconfig" "oai-ran-cuup"
k8s_wait_ready_replicas "deployment" "oai-cu-up" "$_edge_kubeconfig" "oai-ran-cuup"

porch_wait_published_packagerev "oai-ran-du" "edge" "$REVISION"
kpt_wait_pkg "edge" "oai-ran-du" "nephio" "1800"
k8s_wait_exists "nfdeployment" "du-edge" "$_edge_kubeconfig" "oai-ran-du"
k8s_wait_ready_replicas "deployment" "oai-du" "$_edge_kubeconfig" "oai-ran-du"

# Check if the E1Setup Request Response is okay between CU-CP and CU-UP
_wait_for_ran "$_regional_kubeconfig" "Accepting new CU-UP ID" "E1"
# Check if the F1Setup Request Response is okay between DU and CU-CP
_wait_for_ran "$_regional_kubeconfig" "DU uses RRC version" "F1"
