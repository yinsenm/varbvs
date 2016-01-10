%--------------------------------------------------------------------------
% varbvs.m: One-sentence summary of function goes here.
%--------------------------------------------------------------------------
%
% DESCRIPTION:
%    Overview of function goes here.
%
% USAGE:
%    Summary of usage goes here.
%
% INPUT ARGUMENTS:
% Description of input arguments goes here.
%
% OUTPUT ARGUMENTS:
% Description of output arguments goes here.
%
% DETAILS:
%    Detailed description of function goes here.
%
% LICENSE: GPL v3
%
% DATE: December 28, 2015
%
% AUTHORS:
%    List contributors here.
%
% REFERENCES:
%    List of references goes here.
%
% SEE ALSO:
%    List related functions here.
%
% EXAMPLES:
%    Give some examples here.
%
function fit = varbvs (X, Z, y, labels, family, options)

  % Get the number of samples (n) and variables (p).
  [n p] = size(X);

  % (1) CHECK INPUTS
  % ----------------
  % Input X must be single precision.
  if ~isa(X,'single')
    X = single(X);
  end

  % If input Z is not empty, it must be double precision, and must have as
  % many rows as X.
  if ~isempty(Z)
    if size(Z,1) ~= n
      error('Inputs X and Z do not match.');
    end
    Z = double(Z);
  end

  % Add intercept.
  Z = [ones(n,1) Z];

  % Input y must be a double-precision column vector with n elements.
  y = double(y(:));
  if length(y) ~= n
    error('Inputs X and y do not match.');
  end

  % The labels must be a cell array with p elements, or an empty array.
  if nargin < 4
    labels = [];
  end
  if isempty(labels)
    labels = cellfun(@num2str,num2cell(1:p)','UniformOutput',false);
  else
    labels = labels(:);
    if (~iscell(labels) | length(labels) ~= p)
      error('labels must be a cell array with numel(labels) = size(X,2)');
    end
  end
  
  % By default, Y is a quantitative trait (normally distributed).
  if nargin < 5
    family = 'gaussian';
  end
  if isempty(family)
    family = 'gaussian';
  end
  if ~(family == 'gaussian' | family == 'binomial')
    error('family must be gaussian or binomial');
  end
  
  % (2) PROCESS OPTIONS
  % -------------------
  % If the 'options' input argument is not specified, all the options are
  % set to the defaults.
  if nargin < 6
    options = [];
  end
  
  % OPTIONS.TOL
  % Set the convergence tolerance of the co-ordinate ascent updates.
  if isfield(options,'tol')
    tol = options.tol;
  else
    tol = 1e-6;
  end

  % OPTIONS.MAXITER
  % Set the maximum number of inner-loop iterations.
  if isfield(options,'maxiter')
    maxiter = options.maxiter;
  else
    maxiter = 1e4;
  end

  % OPTIONS.VERBOSE
  % Determine whether to output progress to the console.
  if isfield(options,'verbose')
    verbose = options.verbose;
  else
    verbose = true;
  end

  % OPTIONS.SIGMA
  % Get candidate settings for the variance of the residual, if provided.
  % Note that this option is not valid for a binary trait.
  if isfield(options,'sigma')
    sigma        = double(options.sigma(:)');
    update_sigma = false;
    if family == 'binomial'
      error('options.sigma is not valid with family = binomial')
    end
  else
    sigma        = var(y);
    update_sigma = true;
  end

  % OPTIONS.SA
  % Get candidate settings for the prior variance of the coefficients, if
  % provided.
  if isfield(options,'sa')
    sa        = double(options.sa(:)');
    update_sa = false;
  else
    sa        = 1;
    update_sa = true;
  end

  % OPTIONS.LOGODDS
  % Get candidate settings for the prior log-odds of inclusion. This may
  % either be specified as a vector, in which case this is the prior applied
  % uniformly to all variables, or it is a p x ns matrix, where p is the
  % number of variables and ns is the number of candidate hyperparameter
  % settings, in which case the prior log-odds is specified separately for
  % each variable. A default setting is only available if the number of
  % other hyperparameter settings is 1, in which case we select 20 candidate
  % settings for the prior log-odds, evenly spaced between log10(1/p) and
  % log10(0.5). If necessary, I convert the prior log-odds settings to an p
  % x ns matrix.
  if isfield(options,'logodds')
    logodds = double(options.logodds);
  elseif isscalar(sigma) & isscalar(sa)
    logodds = linspace(-log10(p),-0.3,20);
  else
    error('options.logodds must be specified')
  end
  if ismatrix(logodds) & size(logodds,1) == p
    prior_same = false;
  else
    prior_same = true;
    logodds    = repmat(logodds(:)',p,1);
  end

  % Here is where I ensure that the numbers of candidate hyperparameter
  % settings are consistent.
  ns = max([numel(sigma) numel(sa) size(logodds,2)]);
  if isscalar(sigma)
    sigma = repmat(sigma,1,ns);
  end
  if isscalar(sa)
    sa = repmat(sa,1,ns);
  end
  if numel(sigma) ~= ns | numel(sa) ~= ns | size(logodds,2) ~= ns
    error('options.sigma, options.sa and options.logodds are inconsistent')
  end

  % OPTIONS.UPDATE_SIGMA
  % Determine whether to update the residual variance parameter. Note
  % that this option is not valid for a binary trait.
  if isfield(options,'update_sigma')
    update_sigma = options.update_sigma;
    if family == 'binomial'
      error('options.update_sigma is not valid with family = binomial')
    end
  end

  % OPTIONS.UPDATE_SA
  % Determine whether to update the prior variance of the regression
  % coefficients.
  if isfield(options,'update_sa')
    update_sa = options.update_sa;
  end

  % OPTIONS.SA0
  % Get the scale parameter for the scaled inverse chi-square prior.
  if isfield(options,'sa0')
    sa0 = options.sa0;
  else
    sa0 = 0;
  end

  % OPTIONS.N0
  % Get the number of degrees of freedom for the scaled inverse chi-square
  % prior.
  if isfield(options,'n0')
    n0 = options.n0;
  else
    n0 = 0;
  end

  % OPTIONS.ALPHA
  % Set initial estimates of variational parameter alpha.
  initialize_params = true;
  if isfield(options,'alpha')
    alpha = double(options.alpha);
    initialize_params = false;  
    if size(alpha,1) ~= p
      error('options.alpha must have as many rows as X has columns')
    end
    if size(alpha,2) == 1
      alpha = repmat(alpha,1,ns);
    end
  else
    alpha = rand(p,ns);
    alpha = alpha ./ repmat(sum(alpha),p,1);
  end

  % OPTIONS.MU
  % Set initial estimates of variational parameter mu.
  if isfield(options,'mu')
    mu = double(options.mu(:));
    initialize_params = false;  
    if size(mu,1) ~= p
      error('options.mu must have as many rows as X has columns')
    end
    if size(mu,2) == 1
      mu = repmat(mu,1,ns);
    end
  else
    mu = randn(p,ns);
  end

  % OPTIONS.ETA
  % Set initial estimates of variational parameter eta. Note this is only
  % relevant for logistic regression.
  if isfield(options,'eta')
    eta               = double(options.eta);
    initialize_params = false;
    optimize_eta      = false;
    if family ~= 'binomial'
      error('options.eta is only valid for family = binomial');
    end
    if size(eta,1) ~= n
      error('options.eta must have as many rows as X')
    end
    if size(eta,2) == 1
      eta = repmat(eta,1,ns);
    end
  else
    eta               = ones(n,ns);
    optimize_eta      = true;
    initialize_params = true;  
  end

  % OPTIONS.OPTIMIZE_ETA
  % Determine whether to update the variational parameter eta. Note this
  % is only relevant for logistic regression.
  if isfield(options,'eta')
    optimize_eta = options.optimize_eta;
    if family ~= 'binomial'
      error('options.optimize_eta is only valid for family = binomial');
    end
  end
  
  % OPTIONS.INITIALIZE_PARAMS
  % Determine whether to find a good initialization for the variational
  % parameters.
  if isfield(options,'initialize_params')
    initialize_params = options.initialize_params;
  end

  % OPTIONS.NR
  % This is the number of samples to draw of the proportion of variance
  % in Y explained by the fitted model.
  if isfield(options,'nr')
    nr = options.nr;
  else
    nr = 1000;
  end
  
  % TO DO: Allow specification of summary statistics ('Xb') from "fixed"
  % variational estimates for an external set of variables.
  clear options

  % (3) PREPROCESSING STEPS
  % -----------------------
  % Adjust the genotypes and phenotypes so that the linear effects of
  % the covariates are removed. This is equivalent to integrating out
  % the regression coefficients corresponding to the covariates with
  % respect to an improper, uniform prior; see Chipman, George and
  % McCulloch, "The Practical Implementation of Bayesian Model
  % Selection," 2001.
  if family == 'gaussian'
    if size(Z,2) == 1
       X = X - repmat(mean(X),length(y),1);
       y = y - mean(y);
    else

      % This should give the same result as centering the columns of X and
      % subtracting the mean from y when we have only one covariate, the
      % intercept.
      y = y - Z*((Z'*Z)\(Z'*y));
      X = X - Z*((Z'*Z)\(Z'*X));
    end
  end

  % Provide a brief summary of the analysis.
  if verbose
    fprintf('Fitting variational approximation for Bayesian variable ');
    fprintf('selection model.\n');
    fprintf('family:     %-8s',family); 
    fprintf('   num. hyperparameter settings: %d\n',numel(sa));
    fprintf('samples:    %-6d',n); 
    fprintf('     convergence tolerance         %0.1e\n',tol);
    fprintf('variables:  %-6d',p); 
    fprintf('     iid variable selection prior: %s\n',tf2yn(prior_same));
    fprintf('covariates: %-6d',max(0,size(Z,2) - 1));
    fprintf('     fit prior var. of coefs (sa): %s\n',tf2yn(update_sa));
    fprintf('                       ');
    if family == 'gaussian'
      fprintf('fit residual var. (sigma):    %s\n',tf2yn(update_sigma));
    elseif family == 'binomial'
      fprintf('fit approx. factors (eta):    %s\n',tf2yn(optimize_eta));
    end
  end
  
  % (4) INITIALIZE STORAGE FOR THE OUTPUTS
  % --------------------------------------
  % Initialize storage for the variational estimate of the marginal
  % log-likelihood for each hyperparameter setting (logw), and the variances
  % of the regression coefficients (s).
  logw = zeros(1,ns);
  s    = zeros(p,ns);

  % (5) FIT BAYESIAN VARIABLE SELECTION MODEL TO DATA
  % -------------------------------------------------
  if ns == 1
    % Find a set of parameters that locally minimize the K-L
    % divergence between the approximating distribution and the exact
    % posterior.
    if verbose
      fprintf('        variational    max.   incl variance params\n');
      fprintf(' iter   lower bound  change   vars   sigma      sa\n');
    end
    [logw sigma sa alpha mu s eta] = ...
        outerloop(X,Z,y,family,sigma,sa,logodds,alpha,mu,eta,tol,maxiter,...
                  verbose,[],update_sigma,update_sa,optimize_eta,n0,sa0);
    if verbose
      fprintf('\n');
    end
  else
      
    % If a good initialization isn't already provided, find a good
    % initialization for the variational parameters. Repeat for each
    % candidate setting of the hyperparameters.
    if initialize_params
      if verbose
        fprintf('Finding best initialization for %d combinations of ',ns);
        fprintf('hyperparameters.\n');
        fprintf('-iteration-   variational    max.   incl variance params\n');
        fprintf('outer inner   lower bound  change   vars   sigma      sa\n');
      end
      
      % Repeat for each setting of the hyperparameters.
      for i = 1:ns
        [logw(i) sigma(i) sa(i) alpha(:,i) mu(:,i) s(:,i) eta(:,i)] = ...
            outerloop(X,Z,y,family,sigma(i),sa(i),logodds(:,i),alpha(:,i),...
                      mu(:,i),eta(:,i),tol,maxiter,verbose,i,update_sigma,...
                      update_sa,optimize_eta,n0,sa0);
      end
      if verbose
        fprintf('\n');
      end

      % Choose an initialization common to all the runs of the coordinate
      % ascent algorithm. This is chosen from the hyperparameters with
      % the highest variational estimate of the marginal likelihood.
      [ans i] = max(logw);
      alpha   = repmat(alpha(:,i),1,ns);
      mu      = repmat(mu(:,i),1,ns);
      eta     = repmat(eta(:,i),1,ns);
    end
    
    % Compute a variational approximation to the posterior distribution
    % for each candidate setting of the hyperparameters.
    fprintf('Computing marginal likelihood for %d combinations of ',ns);
    fprintf('hyperparameters.\n');
    fprintf('-iteration-   variational    max.   incl variance params\n');
    fprintf('outer inner   lower bound  change   vars   sigma      sa\n');

    % Repeat for each setting of the hyperparameters.
    for i = 1:ns

      % Find a set of parameters that locally minimize the K-L
      % divergence between the approximating distribution and the exact
      % posterior.
      [logw(i) sigma(i) sa(i) alpha(:,i) mu(:,i) s(:,i) eta(:,i)] = ...
          outerloop(X,Z,y,family,sigma(i),sa(i),logodds(:,i),alpha(:,i),...
                    mu(:,i),eta(:,i),tol,maxiter,verbose,i,update_sigma,...
                    update_sa,optimize_eta,n0,sa0);
    end
    if verbose
      fprintf('\n');
    end
  end

  % 5. CREATE FINAL OUTPUT
  % ----------------------
  if family == 'gaussian'
    fit = struct('family',family,'num_covariates',size(Z,2) - 1,...
                 'num_samples',n,'labels',{labels},'n0',n0,'sa0',sa0,...
                 'update_sigma',update_sigma,'update_sa',update_sa,...
                 'prior_same',prior_same,'logw',{logw},'sigma',{sigma},...
                 'sa',sa,'logodds',{logodds},'alpha',{alpha},'mu',{mu},...
                 's',{s});

    % Compute the proportion of variance in Y, after removing linear
    % effects of covariates, explained by the regression model.
    fit.model_pve = varbvspve(X,fit,nr);

    % Compute the proportion of variance in Y, after removing linear
    % effects of covariates, explained by each variable.
    fit.pve = zeros(p,ns);
    sx      = var1(X);
    for i = 1:ns
      sz = sx.*(mu(:,i).^2 + s(:,i));
      fit.pve(:,i) = sz./(sz + sigma(i));
    end
  elseif family == 'binomial'
    fit = struct('logw',logw,'sigma',sigma,'sa',sa,'logodds',logodds,...
                 'alpha',alpha,'mu',mu,'s',s,'eta',eta);
  end

% ------------------------------------------------------------------
% Implements one iteration of the "outer loop".
function [logw, sigma, sa, alpha, mu, s, eta] = ...
        outerloop (X, Z, y, family, sigma, sa, logodds, alpha, mu, eta, ...
                   tol, maxiter, verbose, outer_iter, update_sigma, ...
                   update_sa, optimize_eta, n0, sa0)
  if family == 'gaussian'
    [logw sigma sa alpha mu s] = ...
        varbvsnorm(X,y,sigma,sa,log(10)*logodds,alpha,mu,tol,maxiter,...
                   verbose,outer_iter,update_sigma,update_sa,n0,sa0);
  elseif family == 'binomial' & isempty(Z)
    [logw sa alpha mu s eta] = ...
        varbvsbin(X,y,sa,log(10)*logodds,alpha,mu,eta,tol,maxiter,verbose,...
                  outer_iter,update_sa,optimize_eta,n0,sa0);
  elseif family == 'binomial'
    [logw sa alpha mu s eta] = ...
        varbvsbinz(X,Z,y,sa,log(10)*logodds,alpha,mu,eta,tol,maxiter,...
                   verbose,outer_iter,update_sa,optimize_eta,n0,sa0);
  end

% ------------------------------------------------------------------
function y = tf2yn (x)
  if x
    y = 'yes';
  else
    y = 'no';
  end