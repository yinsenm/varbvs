% This function is used in function 'varbvsbinz' to compute quantities
% useful for the variational approximation to the logistic regression
% factors.
function stats = update_varbvsbinz_stats (X, Z, y, eta)

  % Compute the slope of the conjugate.
  d = slope(eta);

  % Compute the posterior covariance of u (coefficients for Z) given beta
  % (coefficients for X).
  D = diag(sparse(d));
  S = inv(Z'*D*Z);
  
  % Compute matrix dzr = D*Z*R', where R is an upper triangular matrix such
  % that R'*R = S.
  R   = chol(S);
  dzr = D*(Z*R');

  % Compute yhat. 
  yhat = y - 0.5 - dzr*R*(Z'*(y - 0.5));

  % Here, I calculate xy = X'*yhat as (yhat'*X)' and xd = X'*d as (d'*X)' to
  % avoid storing the transpose of X, since X may be large.
  xy = double(yhat'*X)';
  xd = double(d'*X)';

  % Compute the diagonal entries of X'*Dhat*X. For a definition of Dhat,
  % see the Bayesian Analysis journal paper.
  xdx = diagsq(X,d) - diagsq(dzr'*X);

  % Return the result.
  stats = struct('S',S,'d',d,'yhat',yhat,'xy',xy,'xd',xd,'xdx',xdx,'dzr',dzr);
