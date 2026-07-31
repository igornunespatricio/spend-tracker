import { useRef, useState } from "react";
import { Camera, Upload, RefreshCw, Check, AlertCircle } from "lucide-react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { createJob, uploadPhoto, submitJob, getJob, confirmJob } from "@/services/api";
import { CATEGORIES, CATEGORY_LABELS, BEDROCK_MODELS } from "@/types";
import type { ExtractedItem, BedrockModel, Category, JobStatus } from "@/types";
import { useNavigate } from "react-router-dom";

type Step = "select" | "uploading" | "processing" | "review" | "done" | "error";

export default function PhotoUpload(): JSX.Element {
  const navigate = useNavigate();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [step, setStep] = useState<Step>("select");
  const [selectedModel, setSelectedModel] = useState<string>(BEDROCK_MODELS[0].id);
  const [preview, setPreview] = useState<string>("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [jobId, setJobId] = useState<string>("");
  const [editableItems, setEditableItems] = useState<ExtractedItem[]>([]);
  const [errorMsg, setErrorMsg] = useState<string>("");

  // Poll for job status every 3s while processing
  const { data: jobData } = useQuery({
    queryKey: ["job", jobId],
    queryFn: () => getJob(jobId),
    enabled: step === "processing" && !!jobId,
    refetchInterval: (data) => {
      const status: JobStatus = data?.state?.data?.status ?? "PROCESSING";
      if (status === "PENDING_REVIEW" || status === "FAILED") return false;
      return 3000;
    },
    select: (job) => {
      if (job.status === "PENDING_REVIEW") {
        setEditableItems(job.extractedItems.map((i) => ({ ...i })));
        setStep("review");
      } else if (job.status === "FAILED") {
        setErrorMsg(job.errorMessage ?? "Processing failed. Try again.");
        setStep("error");
      }
      return job;
    },
  });

  const uploadMutation = useMutation({
    mutationFn: async () => {
      if (!selectedFile) throw new Error("No file selected");
      setStep("uploading");
      const { jobId: newJobId, uploadUrl } = await createJob(selectedModel);
      await uploadPhoto(uploadUrl, selectedFile);
      await submitJob(newJobId);
      setJobId(newJobId);
      setStep("processing");
    },
    onError: (err: Error) => {
      setErrorMsg(err.message);
      setStep("error");
    },
  });

  const confirmMutation = useMutation({
    mutationFn: () =>
      confirmJob(
        jobId,
        editableItems.map((i) => ({
          description: i.description,
          amount: i.amount,
          category: i.category,
          location: i.location,
        }))
      ),
    onSuccess: () => {
      setStep("done");
      setTimeout(() => navigate("/dashboard"), 2000);
    },
    onError: () => setErrorMsg("Failed to save. Please try again."),
  });

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>): void {
    const file = e.target.files?.[0];
    if (!file) return;
    setSelectedFile(file);
    setPreview(URL.createObjectURL(file));
    setStep("select");
  }

  function updateItem(id: string, field: keyof ExtractedItem, value: string): void {
    setEditableItems((prev) => prev.map((item) => (item.id === id ? { ...item, [field]: value } : item)));
  }

  function removeItem(id: string): void {
    setEditableItems((prev) => prev.filter((item) => item.id !== id));
  }

  if (step === "done") {
    return (
      <div className="flex flex-col items-center justify-center py-24 px-4 text-center">
        <div className="text-5xl mb-4">✅</div>
        <h2 className="text-lg font-bold text-gray-900">Saved!</h2>
        <p className="text-gray-500 text-sm mt-1">Redirecting to dashboard…</p>
      </div>
    );
  }

  if (step === "error") {
    return (
      <div className="p-4">
        <div className="bg-red-50 border border-red-200 rounded-2xl p-5 text-center">
          <AlertCircle className="mx-auto text-red-500 mb-3" size={32} />
          <p className="text-red-700 text-sm font-medium">{errorMsg}</p>
          <button
            onClick={() => { setStep("select"); setPreview(""); setSelectedFile(null); }}
            className="mt-4 text-sm text-primary-600 underline"
          >
            Try again
          </button>
        </div>
      </div>
    );
  }

  if (step === "processing") {
    return (
      <div className="flex flex-col items-center justify-center py-24 px-4 text-center">
        <div className="w-16 h-16 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin mb-6" />
        <h2 className="text-base font-semibold text-gray-800">Analysing your receipt…</h2>
        <p className="text-gray-400 text-sm mt-1">This may take up to 30 seconds</p>
      </div>
    );
  }

  if (step === "review") {
    return (
      <div className="p-4 space-y-4">
        <div className="flex items-center justify-between">
          <h1 className="text-lg font-bold text-gray-900">Review Items</h1>
          <span className="text-xs text-gray-400">{editableItems.length} item(s) found</span>
        </div>

        {editableItems.length === 0 ? (
          <div className="text-center py-12 text-gray-400">
            <p className="text-3xl mb-2">🔍</p>
            <p className="text-sm">No items could be extracted. Try a clearer photo.</p>
            <button
              onClick={() => { setStep("select"); setPreview(""); setSelectedFile(null); }}
              className="mt-3 text-sm text-primary-600 underline"
            >
              Upload another photo
            </button>
          </div>
        ) : (
          <>
            <ul className="space-y-3">
              {editableItems.map((item) => (
                <li key={item.id} className="bg-white rounded-2xl p-4 shadow-sm space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <input
                      value={item.description}
                      onChange={(e) => updateItem(item.id, "description", e.target.value)}
                      className="flex-1 text-sm font-medium text-gray-800 border-b border-transparent focus:border-primary-400 focus:outline-none"
                    />
                    <button onClick={() => removeItem(item.id)} className="text-gray-300 hover:text-red-400 flex-shrink-0">
                      ✕
                    </button>
                  </div>

                  <div className="flex gap-2 items-center">
                    <span className="text-gray-400 text-sm">$</span>
                    <input
                      value={item.amount}
                      onChange={(e) => updateItem(item.id, "amount", e.target.value)}
                      type="number"
                      step="0.01"
                      inputMode="decimal"
                      className="w-24 text-sm border-b border-transparent focus:border-primary-400 focus:outline-none text-gray-800 font-semibold"
                    />
                    <select
                      value={item.category}
                      onChange={(e) => updateItem(item.id, "category", e.target.value)}
                      className="ml-auto text-xs text-gray-600 border border-gray-200 rounded-lg px-2 py-1"
                    >
                      {CATEGORIES.map((cat) => (
                        <option key={cat} value={cat}>{CATEGORY_LABELS[cat]}</option>
                      ))}
                    </select>
                  </div>

                  <input
                    value={item.location}
                    onChange={(e) => updateItem(item.id, "location", e.target.value)}
                    placeholder="Location (optional)"
                    className="w-full text-xs text-gray-500 border-b border-transparent focus:border-primary-400 focus:outline-none"
                  />
                </li>
              ))}
            </ul>

            {editableItems.length > 0 && (
              <div className="bg-gray-50 rounded-xl px-4 py-3 text-sm text-gray-700 font-medium">
                Total: ${editableItems.reduce((s, i) => s + parseFloat(i.amount || "0"), 0).toFixed(2)}
              </div>
            )}

            <div className="flex gap-2 pt-2">
              <button
                onClick={() => { setStep("select"); setPreview(""); setSelectedFile(null); }}
                className="flex-1 py-3 border border-gray-300 rounded-xl text-sm font-medium text-gray-700 flex items-center justify-center gap-1"
              >
                <RefreshCw size={14} /> Retake
              </button>
              <button
                onClick={() => confirmMutation.mutate()}
                disabled={confirmMutation.isPending || editableItems.length === 0}
                className="flex-1 py-3 bg-primary-600 hover:bg-primary-700 disabled:opacity-60 rounded-xl text-sm font-semibold text-white flex items-center justify-center gap-1"
              >
                <Check size={14} /> {confirmMutation.isPending ? "Saving…" : "Confirm & Save"}
              </button>
            </div>
          </>
        )}
      </div>
    );
  }

  // Default: select step
  return (
    <div className="p-4 space-y-5">
      <h1 className="text-lg font-bold text-gray-900">Upload Receipt</h1>

      {/* Model selector */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">AI Model</label>
        <div className="grid grid-cols-1 gap-2">
          {BEDROCK_MODELS.map((model: BedrockModel) => (
            <label key={model.id} className="cursor-pointer">
              <input
                type="radio"
                name="model"
                value={model.id}
                checked={selectedModel === model.id}
                onChange={() => setSelectedModel(model.id)}
                className="sr-only peer"
              />
              <div className="flex items-center gap-3 px-4 py-3 rounded-xl border border-gray-200 peer-checked:border-primary-500 peer-checked:bg-primary-50 transition-colors">
                <div className="flex-1">
                  <p className="text-sm font-medium text-gray-800">{model.label}</p>
                  <p className="text-xs text-gray-400">{model.description}</p>
                </div>
                <div className={`w-4 h-4 rounded-full border-2 ${selectedModel === model.id ? "border-primary-500 bg-primary-500" : "border-gray-300"}`} />
              </div>
            </label>
          ))}
        </div>
      </div>

      {/* Photo area */}
      <div>
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          capture="environment"
          onChange={handleFileChange}
          className="sr-only"
        />

        <button
          onClick={() => fileInputRef.current?.click()}
          className="w-full aspect-video rounded-2xl border-2 border-dashed border-gray-300 hover:border-primary-400 bg-gray-50 flex flex-col items-center justify-center gap-2 transition-colors overflow-hidden"
        >
          {preview ? (
            <img src={preview} alt="Receipt preview" className="w-full h-full object-cover" />
          ) : (
            <>
              <Camera size={36} className="text-gray-400" />
              <p className="text-sm font-medium text-gray-600">Tap to take a photo</p>
              <p className="text-xs text-gray-400">or upload from your gallery</p>
            </>
          )}
        </button>
      </div>

      {selectedFile && (
        <div className="flex gap-2">
          <button
            onClick={() => { setPreview(""); setSelectedFile(null); }}
            className="flex-1 py-3 border border-gray-300 rounded-xl text-sm font-medium text-gray-700 flex items-center justify-center gap-1"
          >
            <RefreshCw size={14} /> Change Photo
          </button>
          <button
            onClick={() => uploadMutation.mutate()}
            disabled={uploadMutation.isPending}
            className="flex-1 py-3 bg-primary-600 hover:bg-primary-700 disabled:opacity-60 rounded-xl text-sm font-semibold text-white flex items-center justify-center gap-1"
          >
            <Upload size={14} /> {uploadMutation.isPending ? "Uploading…" : "Extract Items"}
          </button>
        </div>
      )}

      <p className="text-xs text-gray-400 text-center">
        The AI will extract all spending items from your receipt. You'll be able to review and edit before saving.
      </p>
    </div>
  );
}
