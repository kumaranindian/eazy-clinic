# Laboratory Boundary

Phase 9 (laboratory) does not exist. The doctor can record an investigation **request** (`POST /consultations/{id}/investigations`: testName, code, indication, priority routine/urgent/stat, instructions) stored in `investigation_requests` with `status: requested`, `processing: not_available`. No result, order number, report or lab status is shown or implied; the history view says laboratory results are not available. Phase 9 will consume `investigation_requests` and add results without changing this contract.
