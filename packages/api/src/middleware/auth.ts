import { Request, Response, NextFunction } from 'express';
import { supabase } from '../lib/supabaseClient';

declare global {
  namespace Express {
    interface Request {
      auth?: { user?: any; isService?: boolean };
    }
  }
}

export async function authenticate(req: Request, res: Response, next: NextFunction) {
  try {
    const apiKey = (req.header('x-api-key') || req.query.api_key) as string | undefined;
    const authHeader = req.header('authorization');

    // Service key
    if (apiKey && process.env.API_SERVER_KEY && apiKey === process.env.API_SERVER_KEY) {
      req.auth = { isService: true };
      return next();
    }

    // Bearer token -> supabase
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.slice(7);
      const { data, error } = await supabase.auth.getUser(token);
      if (error || !data?.user) {
        return res.status(401).json({ error: 'Invalid token' });
      }
      req.auth = { user: data.user, isService: false };
      return next();
    }

    return res.status(401).json({ error: 'Unauthorized' });
  } catch (err) {
    console.error('Auth error', err);
    return res.status(500).json({ error: 'Auth failure' });
  }
}

export function requireService(req: Request, res: Response, next: NextFunction) {
  if (req.auth?.isService) return next();
  return res.status(403).json({ error: 'Service key required' });
}
