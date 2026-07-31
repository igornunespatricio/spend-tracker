import { Outlet, useNavigate, useLocation } from "react-router-dom";
import { LayoutDashboard, PlusCircle, Camera, LogOut } from "lucide-react";
import { useAuthStore } from "@/hooks/useAuthStore";

const NAV_ITEMS = [
  { to: "/dashboard", icon: LayoutDashboard, label: "Dashboard" },
  { to: "/add",       icon: PlusCircle,      label: "Add" },
  { to: "/upload",    icon: Camera,          label: "Upload" },
];

export function Layout(): JSX.Element {
  const navigate = useNavigate();
  const location = useLocation();
  const logout = useAuthStore((s) => s.logout);

  function handleLogout(): void {
    logout();
    navigate("/login", { replace: true });
  }

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col max-w-lg mx-auto">
      {/* Header */}
      <header className="bg-white border-b border-gray-200 px-4 py-3 flex items-center justify-between sticky top-0 z-10">
        <div className="flex items-center gap-2">
          <span className="text-xl">💸</span>
          <span className="font-bold text-gray-900 text-base">Spend Tracker</span>
        </div>
        <button
          onClick={handleLogout}
          className="text-gray-500 hover:text-gray-700 p-1.5 rounded-lg hover:bg-gray-100 transition-colors"
          aria-label="Sign out"
        >
          <LogOut size={18} />
        </button>
      </header>

      {/* Page content */}
      <main className="flex-1 overflow-y-auto pb-20">
        <Outlet />
      </main>

      {/* Bottom navigation */}
      <nav className="fixed bottom-0 left-1/2 -translate-x-1/2 w-full max-w-lg bg-white border-t border-gray-200 safe-bottom z-10">
        <div className="flex">
          {NAV_ITEMS.map(({ to, icon: Icon, label }) => {
            const active = location.pathname === to;
            return (
              <button
                key={to}
                onClick={() => navigate(to)}
                className={`flex-1 flex flex-col items-center py-3 gap-0.5 text-xs font-medium transition-colors ${
                  active ? "text-primary-600" : "text-gray-500 hover:text-gray-700"
                }`}
              >
                <Icon size={20} strokeWidth={active ? 2.5 : 1.8} />
                <span>{label}</span>
              </button>
            );
          })}
        </div>
      </nav>
    </div>
  );
}

export default Layout;
