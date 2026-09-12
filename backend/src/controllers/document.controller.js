const asyncHandler = require("../utils/async-handler");
const { sendUploadFile } = require("../utils/send-upload-file");
const {
  listUserDocuments,
  listManageableDocuments,
  createDocumentForUser,
  getDocumentDetails,
  renameDocument,
  deleteDocument,
  getAccessibleDocument,
  listPendingLocalSyncDocuments,
  markDocumentLocalSynced,
} = require("../services/document.service");

const listDocuments = asyncHandler(async (req, res) => {
  const result =
    req.query.scope === "all" && req.user.role === "admin"
      ? await listManageableDocuments(req.user, req.query)
      : await listUserDocuments(req.user.id, req.query);
  res.status(200).json(result);
});

const uploadDocument = asyncHandler(async (req, res) => {
  const document = await createDocumentForUser(req.user.id, req.file, req.body);
  res.status(201).json({ document });
});

const listPendingLocalSync = asyncHandler(async (req, res) => {
  const documents = await listPendingLocalSyncDocuments(req.user);
  res.status(200).json({ documents });
});

const getDocument = asyncHandler(async (req, res) => {
  const document = await getDocumentDetails(req.user, req.params.id);
  res.status(200).json({ document });
});

const downloadDocument = asyncHandler(async (req, res) => {
  const document = await getAccessibleDocument(req.user, req.params.id);
  await sendUploadFile(res, document.filePath, {
    contentType: document.mimeType,
    disposition: "attachment",
    fileName: document.fileName,
    notFoundMessage: "Document file not found.",
    logLabel: "document-download",
  });
});

const renameUserDocument = asyncHandler(async (req, res) => {
  const document = await renameDocument(
    req.user,
    req.params.id,
    req.body.fileName
  );
  res.status(200).json({ document });
});

const deleteUserDocument = asyncHandler(async (req, res) => {
  await deleteDocument(req.user, req.params.id);
  res.status(204).send();
});

const confirmLocalSync = asyncHandler(async (req, res) => {
  const document = await markDocumentLocalSynced(req.user, req.params.id);
  res.status(200).json({ document });
});

module.exports = {
  listDocuments,
  uploadDocument,
  listPendingLocalSync,
  getDocument,
  downloadDocument,
  renameUserDocument,
  deleteUserDocument,
  confirmLocalSync,
};
