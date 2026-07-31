import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { AuthSession } from "@/services/auth";
import { signOut } from "@/services/auth";

interface AuthState {
  session: AuthSession | null;
  setSession: (session: AuthSession | null) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      session: null,
      setSession: (session) => set({ session }),
      logout: () => {
        signOut();
        set({ session: null });
      },
    }),
    { name: "spend-tracker-auth" }
  )
);
