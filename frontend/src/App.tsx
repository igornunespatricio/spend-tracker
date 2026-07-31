import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { useAuthStore } from "@/hooks/useAuthStore";
import Login from "@/pages/Login";
import Dashboard from "@/pages/Dashboard";
import ManualInput from "@/pages/ManualInput";
import PhotoUpload from "@/pages/PhotoUpload";
import Layout from "@/components/Layout";

function ProtectedRoute({ children }: { children: React.ReactNode }): JSX.Element {
  const session = useAuthStore((s) => s.session);
  return session ? <>{children}</> : <Navigate to="/login" replace />;
}

export default function App(): JSX.Element {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/"
          element={
            <ProtectedRoute>
              <Layout />
            </ProtectedRoute>
          }
        >
          <Route index element={<Navigate to="/dashboard" replace />} />
          <Route path="dashboard" element={<Dashboard />} />
          <Route path="add" element={<ManualInput />} />
          <Route path="upload" element={<PhotoUpload />} />
        </Route>
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
