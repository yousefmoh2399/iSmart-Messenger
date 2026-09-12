const assert = require("node:assert/strict");
const test = require("node:test");

const store = require("../src/chat/services/print-job-store");

test("print-job-store: clientRequestId mapping", () => {
  store.clearAll();

  const reqId = "client-req-123";
  const jobId1 = "job-abc";

  // Register new request
  store.registerRequest(reqId, jobId1);

  // Retrieve jobId
  const resolved = store.getJobIdForRequest(reqId);
  assert.equal(resolved, jobId1);

  // Different request should be null
  assert.equal(store.getJobIdForRequest("other-req"), null);

  // Registering empty request does nothing
  assert.equal(store.getJobIdForRequest(""), null);
});

test("print-job-store: job creation and lifecycle", () => {
  store.clearAll();

  const jobId = "job-1";
  const payload = { file: "test.pdf" };

  const job = store.createJob(jobId, payload);
  assert.equal(job.state, "pending");
  assert.equal(job.retryCount, 0);

  // pending -> forwarded
  store.validateAndTransition(jobId, "forwarded");
  assert.equal(store.getJob(jobId).state, "forwarded");

  // forwarded -> processing
  store.validateAndTransition(jobId, "processing");
  assert.equal(store.getJob(jobId).state, "processing");

  // processing -> submitted
  store.validateAndTransition(jobId, "submitted");
  assert.equal(store.getJob(jobId).state, "submitted");

  // submitted is terminal: transitions from submitted should throw
  assert.throws(() => {
    store.validateAndTransition(jobId, "processing");
  }, /Invalid print job state transition/);

  assert.throws(() => {
    store.validateAndTransition(jobId, "failed");
  }, /Invalid print job state transition/);
});

test("print-job-store: failed to processing (retry) increases retryCount", () => {
  store.clearAll();

  const jobId = "job-2";
  store.createJob(jobId, {});

  store.validateAndTransition(jobId, "forwarded");
  store.validateAndTransition(jobId, "failed");
  assert.equal(store.getJob(jobId).state, "failed");
  assert.equal(store.getJob(jobId).retryCount, 0);

  // failed -> processing (retry)
  store.validateAndTransition(jobId, "processing");
  assert.equal(store.getJob(jobId).state, "processing");
  assert.equal(store.getJob(jobId).retryCount, 1);

  // failed -> submitted is disallowed directly
  store.clearAll();
  store.createJob(jobId, {});
  store.validateAndTransition(jobId, "forwarded");
  store.validateAndTransition(jobId, "failed");
  assert.throws(() => {
    store.validateAndTransition(jobId, "submitted");
  }, /Invalid print job state transition/);
});
