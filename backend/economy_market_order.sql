-- ============================================================================
-- Dex Heroes — Ordres « Market » (exécution immédiate au meilleur prix)
-- À coller APRÈS economy.sql + l2 + l3 + l4 + economy_market_api.sql + economy_fees.sql
-- ============================================================================
-- Un ordre Market consomme le carnet directement depuis le SOLDE du joueur
-- (pas de séquestre, pas de reste qui dort). Prix d'exécution = prix des ordres
-- au carnet (les makers). Le preneur (taker) paie le frais taker, les makers le
-- frais maker. Conservation préservée (chaque tx somme à 0 par ressource).
-- ============================================================================

create or replace function public.economy_market_order(p_side text, p_gems numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid; v_sys uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_cfg jsonb; v_maker numeric; v_taker numeric;
  v_remaining numeric; v_filled numeric := 0; v_spent numeric := 0; v_recv numeric := 0;
  v_opp record; v_fill numeric; v_price numeric; v_cash numeric;
  v_bal numeric; v_buyer_gems numeric; v_seller_cash numeric; v_tx uuid; v_guard int := 0;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_side not in ('buy','sell') then return jsonb_build_object('success',false,'error','invalid side'); end if;
  if p_gems <= 0 then return jsonb_build_object('success',false,'error','invalid amount'); end if;

  select value into v_cfg from public.economy_config where key='fees';
  v_maker := coalesce((v_cfg->>'maker')::numeric,0.001);
  v_taker := coalesce((v_cfg->>'taker')::numeric,0.002);

  v_actor := public.economy_ensure_player();
  v_remaining := p_gems;

  loop
    v_guard := v_guard + 1; exit when v_guard > 500;

    if p_side = 'buy' then
      select * into v_opp from public.economy_orders
        where side='sell' and status='open' and gems_remaining>0 and actor_id<>v_actor
        order by price asc, created_at asc limit 1;
    else
      select * into v_opp from public.economy_orders
        where side='buy' and status='open' and gems_remaining>0 and actor_id<>v_actor
        order by price desc, created_at asc limit 1;
    end if;
    exit when not found;

    v_price := v_opp.price;
    v_fill := least(v_remaining, v_opp.gems_remaining);

    if p_side = 'buy' then
      -- L'acheteur (taker) paie le cash depuis son solde ; on limite au finançable.
      select balance into v_bal from public.economy_balances where actor_id=v_actor and resource_id='cash';
      v_bal := coalesce(v_bal,0);
      if v_bal < v_fill * v_price then v_fill := floor(v_bal / v_price); end if;
      exit when v_fill <= 0;
      v_cash := v_fill * v_price;
      v_buyer_gems := v_fill * (1 - v_taker);     -- gems nets (taker)
      v_seller_cash := v_cash * (1 - v_maker);    -- cash net du maker
      v_tx := gen_random_uuid();
      perform public.economy_post_tx(v_tx, jsonb_build_array(
        jsonb_build_object('actor_id',v_actor,'resource_id','cash','delta',-v_cash,'kind','trade','metadata',jsonb_build_object('price',v_price)),
        jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',v_cash,'kind','trade'),
        jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-v_buyer_gems,'kind','trade'),
        jsonb_build_object('actor_id',v_actor,'resource_id','gems','delta',v_buyer_gems,'kind','trade','metadata',jsonb_build_object('price',v_price,'fee',v_fill-v_buyer_gems)),
        jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-v_seller_cash,'kind','trade'),
        jsonb_build_object('actor_id',v_opp.actor_id,'resource_id','cash','delta',v_seller_cash,'kind','trade','metadata',jsonb_build_object('price',v_price,'fee',v_cash-v_seller_cash))
      ));
      insert into public.economy_trades (tx_id,buy_order,sell_order,buyer_id,seller_id,gems,price,cash,fee_gems,fee_cash)
        values (v_tx,null,v_opp.id,v_actor,v_opp.actor_id,v_fill,v_price,v_cash,v_fill-v_buyer_gems,v_cash-v_seller_cash);
      v_spent := v_spent + v_cash;
    else
      -- Le vendeur (taker) livre les gems depuis son solde ; on limite au détenu.
      select balance into v_bal from public.economy_balances where actor_id=v_actor and resource_id='gems';
      v_bal := coalesce(v_bal,0);
      if v_bal < v_fill then v_fill := floor(v_bal); end if;
      exit when v_fill <= 0;
      v_cash := v_fill * v_price;
      v_buyer_gems := v_fill * (1 - v_maker);     -- l'acheteur au carnet = maker (gems)
      v_seller_cash := v_cash * (1 - v_taker);    -- le vendeur = taker (cash)
      -- L'acheteur au carnet a séquestré son cash au v_price (= prix d'exéc) → pas de refund.
      v_tx := gen_random_uuid();
      perform public.economy_post_tx(v_tx, jsonb_build_array(
        jsonb_build_object('actor_id',v_actor,'resource_id','gems','delta',-v_fill,'kind','trade','metadata',jsonb_build_object('price',v_price)),
        jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',v_fill,'kind','trade'),
        jsonb_build_object('actor_id',v_sys,'resource_id','gems','delta',-v_buyer_gems,'kind','trade'),
        jsonb_build_object('actor_id',v_opp.actor_id,'resource_id','gems','delta',v_buyer_gems,'kind','trade','metadata',jsonb_build_object('price',v_price,'fee',v_fill-v_buyer_gems)),
        jsonb_build_object('actor_id',v_sys,'resource_id','cash','delta',-v_seller_cash,'kind','trade'),
        jsonb_build_object('actor_id',v_actor,'resource_id','cash','delta',v_seller_cash,'kind','trade','metadata',jsonb_build_object('price',v_price,'fee',v_cash-v_seller_cash))
      ));
      insert into public.economy_trades (tx_id,buy_order,sell_order,buyer_id,seller_id,gems,price,cash,fee_gems,fee_cash)
        values (v_tx,v_opp.id,null,v_opp.actor_id,v_actor,v_fill,v_price,v_cash,v_fill-v_buyer_gems,v_cash-v_seller_cash);
      v_recv := v_recv + v_seller_cash;
    end if;

    update public.economy_orders set gems_remaining = gems_remaining - v_fill,
      status = case when gems_remaining - v_fill <= 0 then 'filled' else 'open' end where id = v_opp.id;

    v_filled := v_filled + v_fill;
    v_remaining := v_remaining - v_fill;
    exit when v_remaining <= 0;
  end loop;

  if v_filled > 0 then perform public.economy_refresh_price(); end if;
  if v_filled <= 0 then return jsonb_build_object('success',false,'error','aucune liquidité (ou fonds insuffisants)'); end if;
  return jsonb_build_object('success',true,'filled',v_filled,'unfilled',v_remaining,'spent',v_spent,'received',v_recv);
end; $$;
grant execute on function public.economy_market_order(text, numeric) to authenticated;
