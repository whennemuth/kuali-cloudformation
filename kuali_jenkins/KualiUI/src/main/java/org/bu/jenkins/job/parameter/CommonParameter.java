package org.bu.jenkins.job.parameter;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.active_choices.dao.AbstractAwsDAO;
import org.bu.jenkins.active_choices.dao.AbstractDockerDAO;
import org.bu.jenkins.active_choices.dao.AbstractGitDAO;
import org.bu.jenkins.active_choices.dao.EcrDAO;
import org.bu.jenkins.active_choices.html.AbstractParameterView;
import org.bu.jenkins.active_choices.html.ParameterErrorView;
import org.bu.jenkins.active_choices.model.JavaTomcatTag;
import org.bu.jenkins.cli.DockerCommandLineAdapter;
import org.bu.jenkins.cli.GitCommandLineAdapter;
import org.bu.jenkins.cli.GitCommits;
import org.bu.jenkins.cli.GitRefs;
import org.bu.jenkins.cli.RuntimeCommand;
import org.bu.jenkins.job.AbstractParameterSet;
import org.bu.jenkins.job.JobParameterConfiguration;
import org.bu.jenkins.job.JobParameterMetadata;
import org.bu.jenkins.util.Argument;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.Path;
import org.bu.jenkins.util.SimpleHttpHandler;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

import software.amazon.awssdk.services.ecr.model.ImageIdentifier;

public class CommonParameter extends AbstractParameterSet {
	
	public static final String JENKINS_SCRIPT_DIR = "/opt/jenkins-scripts";
	
	private Logger logger = LogManager.getLogger(CommonParameter.class.getName());
	
	public CommonParameter(AWSCredentials credentials) {		
		this.credentials = credentials;
	}
	
	public CommonParameter() {
		this.credentials = AWSCredentials.getInstance();
	}
	
	/**
	 * Acts as a single point of control for determining for which parameter the request is for, building the corresponding
	 * model for rendering in the appropriate view, and returning it to be sent back in the response.
	 * 
	 */
	@SuppressWarnings({ "unchecked", "incomplete-switch" })
	@Override
	public String getRenderedParameter(JobParameterConfiguration config) {
		EntryMessage m = logger.traceEntry("getRenderedParameter(config.getParameterName()={})", config.getParameterName());
		try {
			AbstractParameterView parameterView = getSparseParameterView(config, "org/bu/jenkins/active_choices/html/job-parameter/");
			
			ParameterName parameter = ParameterName.tryValue(config.getParameterName());
			
			parameterView.setContextVariable("include", true);
			parameterView.setContextVariable("deactivate", false);
			if(config.hasInvalidStateMessage()) {
				parameterView.setContextVariable("InvalidStateMessage", config.getInvalidStateMessage());
			}

			String invalidMsg = null;
			GitQueryArguments gitArgs = null;
			GitCommandLineAdapter git = null;
			
			switch(parameter) {
				case ECR_URL:
					AbstractAwsDAO dao = new AbstractAwsDAO(credentials) {
						@Override public Collection<?> getResources() { return null; }					
					};
	
					String url = String.format(
							"%s.dkr.ecr.%s.amazonaws.com", 
							dao.getAccountId(), 
							dao.getRegion().id());
					
					if( ! config.isHtml()) {
						logger.traceExit(m);
						return url;
					}
					
					parameterView.setContextVariable("ParameterValue", url);

					break;
				case ECR_IMAGES:
					String repo = config.getParameterMap().get(QueryStringParms.DOCKER_REPOSITORY_NAME.arg());
					if(Argument.isMissing(repo)) {
						config.setParameterName(ParameterName.INVALID.name());
						config.setInvalidStateMessage(String.format(
							"The request was missing a required parameter: \"%s\"", 
							QueryStringParms.DOCKER_REPOSITORY_NAME.arg()));
						return getRenderedParameter(config);
					}
					EcrDAO ecrDAO = new EcrDAO(credentials).setRepositoryName(repo);
					Set<JavaTomcatTag> images = new TreeSet<JavaTomcatTag>();	
					
					((List<ImageIdentifier>) ecrDAO.getResources()).forEach((imageId) -> {
						images.add(new JavaTomcatTag(
							String.format(
								"%s/%s:%s", 
								ecrDAO.getRegistryId(), 
								ecrDAO.getRepositoryName(), imageId.imageTag())
						));
					});
					
					parameterView.setContextVariable("RepositoryName", repo);
					parameterView.setContextVariable("ImageVersions", images);
					if(images.iterator().hasNext()) {
						parameterView.setContextVariable("SelectedVersion", images.iterator().next().getImage());
					}

					break;
				case DOCKER_IMAGES:
					// TODO: Figure out a way to inject the desired implementation of AbstractDockerDAO into this class, instead of explicitly instantiating it here. Violates inversion of control.
					AbstractDockerDAO docker = new DockerCommandLineAdapter(RuntimeCommand.getCommandInstance());
					parameterView.setContextVariable("DockerImages", docker.getImages());
					parameterView.setContextVariable("SelectedImage", "none");
					break;
				case GIT_REFS: case GIT_COMMIT:
					
					gitArgs = new GitQueryArguments(config);
					
					// TODO: Figure out a way to inject the desired implementation of AbstractGitDAO into this class, instead of explicitly instantiating it here. Violates inversion of control.
					switch(parameter) {
						case GIT_REFS:
							git = new GitRefs(RuntimeCommand.getCommandInstance()); break;
						case GIT_COMMIT:
							git = new GitCommits(RuntimeCommand.getCommandInstance()); break;
					}
					
					// Validate the parameters
					if( ! Argument.isMissing(gitArgs.getRefType())) {
						if(Argument.isMissing(gitArgs.getRemoteUrl())) {
							invalidMsg = gitArgs.getMissingGitRemoteUrlMessage();
						}
						else {
							git.setRefType(AbstractGitDAO.RefType.get(gitArgs.getRefType()));
							git.setRemoteUrl(gitArgs.getRemoteUrl());
							if( ! Path.isWindows) {
								git.setScriptDir(JENKINS_SCRIPT_DIR);
							}
							if(gitArgs.cannotUseToken()) {
								if(gitArgs.getSshKeyPath() == null) {
									invalidMsg = gitArgs.getInsufficientCredentialsMessage();
								}
								else {
									git.setSshKeyPath(gitArgs.getSshKeyPath());
								}
							}
							else {
								git.setUser(gitArgs.getUsername());
								git.setPersonalAccessToken(gitArgs.getPersonalAccessToken());
							}
						}
					}
					else {						
						invalidMsg = gitArgs.getMissingRefTypeMessage();
					}
					
					// Render the html for the parameter
					if(invalidMsg != null) {
						return getRenderedInvalidMessage(config, invalidMsg);
					}
					else {
						switch(parameter) {
							case GIT_REFS:
								if(ParameterName.GIT_REFS.equals(parameter)) {
									List<String> refs = git.getOutputList();
									parameterView.setContextVariable("RefType", git.getRefType().name().toLowerCase());
									parameterView.setContextVariable("GitRefs", refs);
									parameterView.setContextVariable("SelectedRef", "none");												
								}
								break;
							case GIT_COMMIT:
								String ref = gitArgs.getRefValue();
								if(Argument.isMissing(ref)) {
									return getRenderedInvalidMessage(config, gitArgs.getMissingRefValueMessage());
								}
								git.setRefValue(ref);
								String id = git.getOutput();
								parameterView.setContextVariable("RefType", git.getRefType().name().toLowerCase());
								parameterView.setContextVariable("GitCommit", id);
								break;	
						}
						if(git.hasError()) {
							logger.traceExit(m);
							return new ParameterErrorView(git.getErrorOutput()).render();
						}
					}
					break;
				case INVALID:
					break;
				default:
					break;			
			}
			
			logger.traceExit(m);
			return parameterView.render();
		} 
		catch (Exception e) {
			e.printStackTrace();
			logger.traceExit(m);
			return stackTraceToHTML(e);
		}
	}
	
	String getRenderedInvalidMessage(JobParameterConfiguration config, String msg) {
		config.setParameterName(ParameterName.INVALID.name());
		config.setInvalidStateMessage(msg);
		return getRenderedParameter(config);		
	}

	@Override
	public JobParameterMetadata[] getJobParameterMetadata() {
		return ParameterName.values();
	}

	@Override
	public void checkJobParameterConfig(JobParameterConfiguration config) {
		return;
	}
		
	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		AbstractParameterSet parms = new CommonParameter(AWSCredentials.getInstance(namedArgs));
		final String parmNameKey = QueryStringParms.PARAMETER_NAME.arg();
		final String dev = namedArgs.get("developmentMode");
		
		parms.setAjaxHost(namedArgs.get("ajax-host", "127.0.0.1"));
		SimpleHttpHandler handler = new SimpleHttpHandler() {
			@Override public String getHtml(Map<String, String> parameters) {
				try {
					String parmName = parameters.get(parmNameKey);
					String invalidStateMsg = null;
					if(parmName == null) {
						parmName = namedArgs.get(parmNameKey);
					}
					if(parmName == null) {
						invalidStateMsg = "The job parameter name was missing from the request!";					
						parmName = ParameterName.INVALID.name();
					}
					else if(ParameterName.tryValue(parmName) == null) {
						invalidStateMsg = String.format("No such job parameter:\" %s\"", parmName);					
						parmName = ParameterName.INVALID.name();
					}
					JobParameterConfiguration config = 
							JobParameterConfiguration.getActiveChoicesFieldInstance(parmName.toUpperCase())
							.setParameterMap(parameters)
							.setHtml( ! "false".equalsIgnoreCase(parameters.get(QueryStringParms.HTML.arg())))
							.setRenderName( ! "false".equalsIgnoreCase(parameters.get(QueryStringParms.RENDER_NAME.arg())))
							.setRenderDescription( "true".equalsIgnoreCase(parameters.get(QueryStringParms.RENDER_DESCRIPTION.arg())))
							.setInvalidStateMessage(invalidStateMsg)
							.setDevelopmentMode(Boolean.valueOf(dev));
					
					return parms.getRenderedParameter(config);
				} 
				catch (Exception e) {
					e.printStackTrace(System.out);
					return stackTraceToHTML(e);
				}
			}};
			
		handler.setPort(namedArgs.getInt("port"));
		
		if(namedArgs.getBoolean("browser")) {			
			/**
			 * Get all of the named args except the those that have nothing to do with request parameters.
			 * What remains will be used to construct a query string for visit with browser.
			 */
			Map<String, String> requestParms = namedArgs.getAllNamed(QueryStringParms.asArgArray());
			
			handler.visitWithBrowser(true, requestParms);				
		}
		else {
			handler.start();
		}
	}
}
