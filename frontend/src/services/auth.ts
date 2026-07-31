import {
  AuthenticationDetails,
  CognitoUser,
  CognitoUserPool,
  CognitoUserSession,
} from "amazon-cognito-identity-js";

const userPool = new CognitoUserPool({
  UserPoolId: import.meta.env.VITE_COGNITO_USER_POOL_ID,
  ClientId: import.meta.env.VITE_COGNITO_CLIENT_ID,
});

export interface AuthSession {
  userId: string;
  email: string;
  idToken: string;
  accessToken: string;
}

export function signIn(email: string, password: string): Promise<AuthSession> {
  return new Promise((resolve, reject) => {
    const cognitoUser = new CognitoUser({ Username: email, Pool: userPool });
    const authDetails = new AuthenticationDetails({ Username: email, Password: password });

    cognitoUser.authenticateUser(authDetails, {
      onSuccess: (session: CognitoUserSession) => {
        resolve({
          userId: session.getIdToken().payload.sub,
          email: session.getIdToken().payload.email,
          idToken: session.getIdToken().getJwtToken(),
          accessToken: session.getAccessToken().getJwtToken(),
        });
      },
      onFailure: reject,
      newPasswordRequired: (_userAttributes) => {
        reject(new Error("PASSWORD_CHANGE_REQUIRED"));
      },
    });
  });
}

export function signOut(): void {
  userPool.getCurrentUser()?.signOut();
}

export function getSession(): Promise<AuthSession | null> {
  return new Promise((resolve) => {
    const user = userPool.getCurrentUser();
    if (!user) return resolve(null);

    user.getSession((err: Error | null, session: CognitoUserSession | null) => {
      if (err || !session?.isValid()) return resolve(null);
      resolve({
        userId: session.getIdToken().payload.sub,
        email: session.getIdToken().payload.email,
        idToken: session.getIdToken().getJwtToken(),
        accessToken: session.getAccessToken().getJwtToken(),
      });
    });
  });
}
