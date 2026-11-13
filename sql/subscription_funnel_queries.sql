Query §3.1 - subscription funnel by country (SQL)
  
WITH base_user_flags AS (
  SELECT u.user_id, u.country,
    MAX(CASE WHEN t.transaction_type='trial_start' AND t.plan_id='P01' THEN 1 ELSE 0 END) as has_trial,
    MAX(CASE WHEN t.transaction_type='first_payment' AND t.plan_id IN ('P02','P03','P04','P05') THEN 1 ELSE 0 END) as has_first_payment,
    MAX(CASE WHEN t.transaction_type='renewal' THEN 1 ELSE 0 END) as has_renewal,
    MAX(CASE WHEN t.transaction_type='upgrade' THEN 1 ELSE 0 END) as has_upgrade
  FROM users u LEFT JOIN transactions t ON u.user_id=t.user_id
  GROUP BY u.user_id, u.country ),
country_aggregates AS (
  SELECT country, COUNT(user_id) as total_signups, SUM(has_trial) as total_trials,
    SUM(has_first_payment) as total_first_payments,
    SUM(CASE WHEN has_first_payment=1 AND has_trial=0 THEN 1 ELSE 0 END) as paid_without_trial,
    SUM(has_renewal) as total_renewals, SUM(has_upgrade) as total_upgrades,
    SUM(CASE WHEN has_trial=1 AND has_first_payment=1 THEN 1 ELSE 0 END) as trial_and_paid
  FROM base_user_flags GROUP BY country )
SELECT country, total_signups, total_trials, total_first_payments, paid_without_trial,
  total_renewals, total_upgrades,
  ROUND(total_trials*100.0/NULLIF(total_signups,0),2) as signup_to_trial_pct,
  ROUND(total_first_payments*100.0/NULLIF(total_signups,0),2) as signup_to_payment_pct,
  ROUND(trial_and_paid*100.0/NULLIF(total_trials,0),2) as trial_to_payment_pct,
  ROUND(total_renewals*100.0/NULLIF(total_first_payments,0),2) as payment_to_renewal_pct,
  ROUND(total_upgrades*100.0/NULLIF(total_first_payments,0),2) as payment_to_upgrade_pct,
  ROUND(paid_without_trial*100.0/NULLIF(total_first_payments,0),2) as direct_payments_share_pct
FROM country_aggregates ORDER BY total_signups DESC;

____________________________________________________________________

Query §3.2 - stacked-column data by transaction type (SQL)

SELECT DATE_FORMAT(date,'%m.%Y') AS month,
  ROUND(SUM(CASE WHEN transaction_type='first_payment' THEN amount_usd ELSE 0 END),2) AS first_payment,
  ROUND(SUM(CASE WHEN transaction_type='renewal' THEN amount_usd ELSE 0 END),2) AS renewal,
  ROUND(SUM(CASE WHEN transaction_type='upgrade' THEN amount_usd ELSE 0 END),2) AS upgrade
FROM transactions
WHERE transaction_type IN ('first_payment','renewal','upgrade')
GROUP BY DATE_FORMAT(date,'%Y-%m'), DATE_FORMAT(date,'%m.%Y')
ORDER BY STR_TO_DATE(CONCAT('01.',month),'%d.%m.%Y') ASC;

______________________________________________________________________

Query §3.5 - trial-to-paid conversion analysis (SQL)

WITH user_trials AS (SELECT DISTINCT user_id FROM transactions WHERE transaction_type='trial_start'),
user_payments AS (SELECT DISTINCT user_id FROM transactions WHERE transaction_type='first_payment')
SELECT u.country, u.acquisition_channel,
  COUNT(DISTINCT t.user_id) AS total_trials,
  COUNT(DISTINCT p.user_id) AS total_paid_users,
  CASE WHEN COUNT(DISTINCT t.user_id)=0 THEN 0
       ELSE ROUND(100.0*COUNT(DISTINCT p.user_id)/COUNT(DISTINCT t.user_id),2) END AS conversion_rate_pct
FROM users u
INNER JOIN user_trials t ON u.user_id=t.user_id
LEFT JOIN user_payments p ON u.user_id=p.user_id
GROUP BY u.country, u.acquisition_channel ORDER BY u.country, conversion_rate_pct DESC;

_____________________________________________________________________

Query §3.6 - unit economics by country: LTV, CAC, ROI (SQL)

WITH user_revenue AS (
  SELECT u.user_id, u.country, COALESCE(SUM(t.amount_usd),0) AS total_spent
  FROM users u LEFT JOIN transactions t ON u.user_id=t.user_id GROUP BY u.user_id, u.country ),
country_users_metrics AS (
  SELECT country, COUNT(user_id) AS total_users, SUM(total_spent) AS total_revenue
  FROM user_revenue GROUP BY country ),
country_marketing_metrics AS (
  SELECT country, SUM(spend_usd) AS total_marketing_spend FROM marketing_spend GROUP BY country )
SELECT u.country, u.total_users AS acquired_users,
  ROUND(u.total_revenue,2) AS total_revenue, ROUND(m.total_marketing_spend,2) AS total_marketing_spend,
  -- LTV = total country revenue / number of users from that country
  CASE WHEN u.total_users>0 THEN ROUND((u.total_revenue/u.total_users),2) ELSE 0 END AS LTV,
  CASE WHEN u.total_users>0 THEN ROUND((m.total_marketing_spend/u.total_users),2) ELSE 0 END AS CAC,
  CASE WHEN m.total_marketing_spend>0 THEN ROUND((u.total_revenue/m.total_marketing_spend),2) ELSE 0 END AS LTV_to_CAC_ratio
FROM country_users_metrics u
LEFT JOIN country_marketing_metrics m ON u.country=m.country ORDER BY total_revenue DESC;

_____________________________________________________________________

Query §3.7 - unit economics by acquisition channel (SQL)

WITH user_revenue AS (
  SELECT u.acquisition_channel, COUNT(DISTINCT u.user_id) as total_users,
    COUNT(DISTINCT CASE WHEN t.transaction_type='first_payment' THEN u.user_id END) as paying_users,
    SUM(CASE WHEN t.transaction_type='refund' THEN -t.amount_usd ELSE COALESCE(t.amount_usd,0) END) as net_revenue
  FROM users u LEFT JOIN transactions t ON u.user_id=t.user_id GROUP BY u.acquisition_channel ),
channel_spend AS (SELECT channel, SUM(spend_usd) as total_spend FROM marketing_spend GROUP BY channel)
SELECT r.acquisition_channel as channel_name, r.total_users, r.paying_users, r.net_revenue,
  COALESCE(s.total_spend,0) as total_spend,
  ROUND(r.net_revenue/NULLIF(r.paying_users,0),2) as LTV,
  ROUND(COALESCE(s.total_spend,0)/NULLIF(r.paying_users,0),2) as CAC,
  ROUND((r.net_revenue/NULLIF(r.paying_users,0))/NULLIF((COALESCE(s.total_spend,0)/NULLIF(r.paying_users,0)),0),2) as LTV_to_CAC_ratio
FROM user_revenue r LEFT JOIN channel_spend s ON r.acquisition_channel=s.channel;

________________________________________________________________________________

Query §3.9 - CAC matrix with global-SMM allocation (SQL)

WITH raw_spend AS (  -- local spend (excluding Global)
  SELECT country, channel, SUM(spend_usd) AS direct_spend FROM marketing_spend
  WHERE country!='Global' GROUP BY country, channel ),
global_smm_spend AS (  -- total global SMM + Content
  SELECT SUM(spend_usd) AS total_smm_spend FROM marketing_spend
  WHERE channel='SMM + Content' AND country='Global' ),
new_paid_customers AS (  -- unique paid users by country & channel
  SELECT u.country, u.acquisition_channel AS channel, COUNT(DISTINCT u.user_id) AS new_paid_users
FROM users u INNER JOIN transactions t ON u.user_id=t.user_id
  WHERE t.transaction_type='first_payment' GROUP BY u.country, u.acquisition_channel ),
smm_allocation_weights AS (  -- country weight for ASO & Referral
  SELECT country, channel, new_paid_users,
    new_paid_users/SUM(new_paid_users) OVER(PARTITION BY channel) AS allocation_weight
  FROM new_paid_customers WHERE channel IN ('ASO Organic','Referral') ),
final_spend_and_cac AS (  -- direct + allocated SMM -> net CAC
  SELECT c.country, c.channel,
    CASE WHEN c.channel NOT IN ('ASO Organic','Referral') THEN COALESCE(s.direct_spend,0)/c.new_paid_users
         ELSE (COALESCE(s.direct_spend,0) + (g.total_smm_spend*0.5*COALESCE(w.allocation_weight,0)))/c.new_paid_users
    END AS cac_value
  FROM new_paid_customers c
  LEFT JOIN raw_spend s ON c.country=s.country AND c.channel=s.channel
  LEFT JOIN smm_allocation_weights w ON c.country=w.country AND c.channel=w.channel
  CROSS JOIN global_smm_spend g )
SELECT country AS Country,
  ROUND(SUM(CASE WHEN channel='Facebook Ads' THEN cac_value ELSE 0 END),2) AS facebook_ads,
  ROUND(SUM(CASE WHEN channel='Google Ads' THEN cac_value ELSE 0 END),2) AS google_ads,
  ROUND(SUM(CASE WHEN channel='Apple Search Ads' THEN cac_value ELSE 0 END),2) AS apple_search_ads,
  ROUND(SUM(CASE WHEN channel='TikTok Ads' THEN cac_value ELSE 0 END),2) AS tiktok_ads,
  ROUND(SUM(CASE WHEN channel='Influencer' THEN cac_value ELSE 0 END),2) AS influencer,
  ROUND(SUM(CASE WHEN channel='ASO Organic' THEN cac_value ELSE 0 END),2) AS aso_organic,
  ROUND(SUM(CASE WHEN channel='Referral' THEN cac_value ELSE 0 END),2) AS referral
FROM final_spend_and_cac WHERE country IN ('US','UK','DE','BR','MX','PL')
GROUP BY country ORDER BY FIELD(country,'US','UK','DE','BR','MX','PL');




  
