
-- Day 1: unified auth helper functions + wallet ensure RPC

-- can_access_admin: any admin role (operations, finance, god, legacy admin)
CREATE OR REPLACE FUNCTION public.can_access_admin(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
      AND role IN ('admin','operations_admin','finance_admin','god_admin')
  );
$$;

-- can_manage_wallet: god_admin or finance_admin only
CREATE OR REPLACE FUNCTION public.can_manage_wallet(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
      AND role IN ('finance_admin','god_admin')
  );
$$;

-- can_manage_operations: god_admin or operations_admin
CREATE OR REPLACE FUNCTION public.can_manage_operations(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
      AND role IN ('operations_admin','god_admin')
  );
$$;

-- wallet_ensure: makes sure the caller has a wallet of the given party_type.
-- Returns the wallet id. Safe to call from the client (auth.uid() enforced).
CREATE OR REPLACE FUNCTION public.wallet_ensure(_party_type text DEFAULT 'client')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF _party_type NOT IN ('client','driver') THEN
    RAISE EXCEPTION 'invalid_party_type';
  END IF;

  SELECT id INTO v_id
  FROM public.wallets
  WHERE owner_user_id = v_uid AND party_type = _party_type;

  IF v_id IS NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (v_uid, _party_type)
    ON CONFLICT (owner_user_id, party_type) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      SELECT id INTO v_id FROM public.wallets
      WHERE owner_user_id = v_uid AND party_type = _party_type;
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.wallet_ensure(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_wallet(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_operations(uuid) TO authenticated;
