function a2_analise_wcet_wcrt(raizRepositorio)
%A2_ANALISE_WCET_WCRT Consolida envelope temporal e RTA de prioridade fixa.
% Os CSVs brutos permanecem imutaveis. A estimativa de WCET e baseada em
% medicao (MB-WCET), com margem explicita de 5%; nao constitui prova estatica.

if nargin < 1 || strlength(string(raizRepositorio)) == 0
    diretorioScript = fileparts(mfilename('fullpath'));
    raizRepositorio = fileparts(diretorioScript);
end
raizRepositorio = string(raizRepositorio);
dirResultados = fullfile(raizRepositorio,'resultados');
assert(isfolder(dirResultados),'Repositorio invalido: %s',raizRepositorio);

set(groot,'defaultFigureColor','w','defaultAxesColor','w', ...
    'defaultAxesXColor','k','defaultAxesYColor','k', ...
    'defaultAxesZColor','k','defaultTextColor','k');

fontes = [ ...
    "e3",  fullfile(dirResultados,'traces','e3','E3_TRACE.csv');
    "e4",  fullfile(dirResultados,'traces','e4','E4_TRACE.csv');
    "e5",  fullfile(dirResultados,'traces','e5','E5_TRACE.csv');
    "e6",  fullfile(dirResultados,'traces','e6','E6_TRACE.csv');
    "e8",  fullfile(dirResultados,'traces','e8','E8_TRACE.csv')];

dados = table();
for k = 1:size(fontes,1)
    t = lerCsv(fontes(k,2));
    t.experimento = repmat(fontes(k,1),height(t),1);
    dados = [dados; t]; %#ok<AGROW>
end

arquivoE5b = fullfile(dirResultados,'traces','e5b', ...
    'E5B_TRACE.csv');
stress = lerCsv(arquivoE5b);
arquivoE9 = fullfile(dirResultados,'metricas','e9', ...
    'E9_METRICAS.csv');
e9 = lerCsv(arquivoE9);
arquivoE7 = fullfile(dirResultados,'traces','e7', ...
    'E7_TRACE.csv');
falhasHeartbeat = lerCsv(arquivoE7);
detE8 = removevars(dados(string(dados.tarefa)=="DET_HB",:),'experimento');
falhasHeartbeat = [falhasHeartbeat; detE8];

dirA2 = fullfile(dirResultados,'metricas','a2');
dirFig = fullfile(dirResultados,'figuras','impressao');
if ~isfolder(dirA2), mkdir(dirA2); end
if ~isfolder(dirFig), mkdir(dirFig); end

[estatisticas,observados] = consolidarEstatisticas(dados);
[temporal,wcrt] = construirModelo(estatisticas,observados,dados,stress,e9, ...
    falhasHeartbeat);

writetable(estatisticas,fullfile(dirA2,'A2_WCET_MEDIDO.csv'));
writetable(temporal,fullfile(dirA2,'A2_TABELA_TEMPORAL.csv'));
writetable(wcrt,fullfile(dirA2,'A2_WCRT.csv'));

gerarFiguraWcet(estatisticas,temporal,dirFig);
gerarFiguraWcrt(wcrt,dirFig);

fprintf('A2 concluida. Resultados: %s\n',dirA2);
end

function t = lerCsv(arquivo)
assert(isfile(arquivo),'Fonte ausente: %s',arquivo);
o = detectImportOptions(arquivo,'Delimiter',',','VariableNamingRule','preserve');
t = readtable(arquivo,o);
end

function [s,obs] = consolidarEstatisticas(dados)
ordem = ["ATUACAO";"SUPERVISAO";"CONTROLE";"AQUISICAO"];
n = zeros(4,1); media = zeros(4,1); desvio = zeros(4,1);
cv = zeros(4,1); p95 = zeros(4,1); p99 = zeros(4,1);
maxDemanda = zeros(4,1); maxDecorrido = zeros(4,1);
maxResposta = zeros(4,1); maxBloqueio = zeros(4,1);

for k = 1:4
    g = dados(string(dados.tarefa)==ordem(k),:);
    assert(~isempty(g),'Tarefa ausente: %s',ordem(k));
    bloqueio = double(g.bloqueio_us);
    bloqueio(~isfinite(bloqueio)) = 0;
    demanda = double(g.execucao_us) - bloqueio;
    if ordem(k)=="AQUISICAO"
        % O timestamp final da aquisição ocorre depois de liberar o mutex.
        % Se a supervisão estava bloqueada, ela preempta a aquisição antes
        % desse timestamp. Retira-se somente a demanda própria da supervisão
        % cujo intervalo cruza cada janela da aquisição.
        sup = dados(string(dados.tarefa)=="SUPERVISAO",:);
        supDemanda = double(sup.execucao_us) - double(sup.bloqueio_us);
        for m = 1:height(g)
            cruza = double(sup.inicio_us) < double(g.termino_us(m)) & ...
                double(sup.termino_us) > double(g.inicio_us(m));
            demanda(m) = demanda(m) - sum(supDemanda(cruza));
        end
    end
    n(k) = numel(demanda);
    media(k) = mean(demanda);
    desvio(k) = std(demanda);
    cv(k) = 100*desvio(k)/media(k);
    p95(k) = percentilNR(demanda,0.95);
    p99(k) = percentilNR(demanda,0.99);
    maxDemanda(k) = max(demanda);
    maxDecorrido(k) = max(double(g.execucao_us));
    maxResposta(k) = max(double(g.resposta_us));
    maxBloqueio(k) = max(bloqueio);
end

s = table(ordem,n,media,desvio,cv,p95,p99,maxDemanda,maxDecorrido, ...
    maxResposta,maxBloqueio,'VariableNames', ...
    {'tarefa','amostras','media_us','desvio_us','cv_pct','p95_us', ...
     'p99_us','max_demanda_us','max_decorrido_us','max_resposta_us', ...
     'max_bloqueio_us'});
obs = containers.Map(cellstr(ordem),num2cell((1:4)'));
end

function q = percentilNR(x,p)
x = sort(x(:));
q = x(max(1,ceil(p*numel(x))));
end

function [temporal,wcrt] = construirModelo(s,idx,dados,stress,e9,falhasHeartbeat)
nomes = ["T_Atuacao";"T_Watchdog";"T_Supervisao";"T_Controle";"T_Aquisicao"; ...
    "T_Comunicacao";"T_Telemetria";"T_Carga"];
tipo = ["esporadica";"periodica";"periodica/notificavel";"sucessora";"periodica"; ...
    "aperiodica";"aperiodica";"periodica de teste"];
ativacao = ["comando/alarme";"heartbeat";"500 ms/evento";"nova amostra";"5,715 s"; ...
    "UART";"fila";"configuravel"];
prioridade = [8;7;6;5;4;3;2;1];
nucleo = [1;1;1;1;1;0;0;1];
periodo_us = [5715000;5000;500000;5715000;5715000;NaN;NaN;NaN];
deadline_us = [20000;20000;500000;100000;600000;100000;5715000;NaN];

iAt = idx('ATUACAO'); iSu = idx('SUPERVISAO');
iCt = idx('CONTROLE'); iAq = idx('AQUISICAO');
detHb = falhasHeartbeat(string(falhasHeartbeat.tarefa)=="DET_HB",:);
assert(height(detHb)==15,'Quantidade inesperada de deteccoes de heartbeat.');
maxWd = max(double(detHb.execucao_us));
maxRespostaWd = max(double(detHb.resposta_us));
hb = dados(string(dados.tarefa)=="HB_RX",:);
maxHb = max(double(hb.execucao_us));
fmt = e9(string(e9.operacao)=="SNPRINTF_TRACE",:);
maxFmtUs = double(fmt.max_ns)/1000;

c_observado_us = [s.max_demanda_us(iAt);maxWd;s.max_demanda_us(iSu); ...
    s.max_demanda_us(iCt);s.max_demanda_us(iAq);maxHb;maxFmtUs;NaN];
maxDecorrido = [s.max_decorrido_us(iAt);maxWd;s.max_decorrido_us(iSu); ...
    s.max_decorrido_us(iCt);s.max_decorrido_us(iAq);maxHb;NaN;NaN];
maxResposta = [s.max_resposta_us(iAt);maxRespostaWd;s.max_resposta_us(iSu); ...
    s.max_resposta_us(iCt);s.max_resposta_us(iAq);max(double(hb.resposta_us)); ...
    NaN;NaN];

% Margem de 5%, arredondada para cima, nas tarefas criticas.
c_mbwcet_us = [110;20;82000;600;330000;NaN;NaN;NaN];
overhead_us = [160;0;0;0;0;NaN;NaN;NaN];
orcamento_rta_us = c_mbwcet_us + overhead_us;
orcamento_inicial_us = [2000;NaN;80000;10000;300000;5000;25000;NaN];
orcamento_operacional_us = [orcamento_rta_us(1:5);5000;25000;NaN];

stressSup = stress(string(stress.tarefa)=="SUPERVISAO",:);
bObs = max(double(stressSup.bloqueio_us));
assert(bObs==308864,'Bloqueio maximo inesperado no E5b.');
b_analise_us = [0;0;325000;0;0;NaN;NaN;NaN];

natureza = ["MB-WCET + margem e despacho";"MB-WCET + margem"; ...
    "MB-WCET + margem";"MB-WCET + margem"; ...
    "envelope ajustado + margem; espera ocupada do ADC incluida"; ...
    "orcamento de projeto; heartbeat observado"; ...
    "orcamento de projeto; formatacao observada";"somente experimental"];
recurso = ["PWM/latch";"heartbeat/latch";"ADC/mutex";"estado do controlador";"ADC/mutex"; ...
    "UART";"UART/fila";"CPU de teste"];

temporal = table(nomes,tipo,ativacao,periodo_us,deadline_us,prioridade,nucleo, ...
    c_observado_us,maxDecorrido,maxResposta,c_mbwcet_us,overhead_us, ...
    orcamento_rta_us,orcamento_inicial_us,orcamento_operacional_us, ...
    b_analise_us,recurso,natureza,'VariableNames', ...
    {'tarefa','tipo','ativacao','periodo_us','deadline_us','prioridade', ...
     'nucleo','c_observado_us','execucao_decorrida_max_us', ...
     'resposta_observada_max_us','c_mbwcet_us','overhead_despacho_us', ...
     'orcamento_rta_us','orcamento_inicial_us','orcamento_operacional_us', ...
     'bloqueio_analise_us','recurso','natureza_limite'});

% RTA de prioridade fixa no nucleo 1. Controle e atuacao usam 5,715 s como
% separacao minima no cenario nominal. Eventos de falha sao analisados no E8.
q = orcamento_rta_us(1:5);
b = b_analise_us(1:5);
t = periodo_us(1:5);
d = deadline_us(1:5);
r = zeros(5,1);
iteracoes = zeros(5,1);
for i = 1:5
    atual = q(i)+b(i);
    for it = 1:100
        interferencia = 0;
        for j = 1:i-1
            interferencia = interferencia + ceil(atual/t(j))*q(j);
        end
        prox = q(i)+b(i)+interferencia;
        if prox==atual, break; end
        atual=prox;
    end
    r(i)=prox; iteracoes(i)=it;
end

% Para a deteccao de heartbeat, soma-se ao WCRT da tarefa o periodo de
% varredura: o vencimento pode ocorrer logo depois de uma verificacao.
rLimite = r;
rLimite(2) = r(2) + t(2);
respObs = maxResposta(1:5);
margem = d-rLimite;
uso = 100*rLimite./d;
usoObs = 100*respObs./d;
wcrt = table(nomes(1:5),prioridade(1:5),t,d,c_observado_us(1:5), ...
    c_mbwcet_us(1:5),overhead_us(1:5),q,b,rLimite,respObs,margem,uso,usoObs, ...
    iteracoes,'VariableNames',{'tarefa','prioridade','periodo_us', ...
    'deadline_us','c_observado_us','c_mbwcet_us','overhead_us', ...
    'orcamento_rta_us','bloqueio_us','wcrt_us','resposta_observada_max_us', ...
    'margem_us','uso_deadline_wcrt_pct','uso_deadline_observado_pct', ...
    'iteracoes'});

atuacoes = dados(string(dados.tarefa)=="ATUACAO",:);
e2eObs = max(double(atuacoes.resposta_fim_a_fim_us));
e2eR = r(5)+r(4)+r(1);
linha = {"CADEIA_E2E",NaN,5715000,5715000,NaN,NaN,NaN,NaN,NaN, ...
    e2eR,e2eObs,5715000-e2eR,100*e2eR/5715000,100*e2eObs/5715000,NaN};
wcrt = [wcrt; linha];
end

function fig = figuraColuna(altura)
fig=figure('Color','w','Visible','off','Units','inches', ...
    'Position',[1 1 3.50 altura]);
end

function preparar(ax)
ax.FontName='Times New Roman'; ax.FontSize=9; ax.LineWidth=0.8;
ax.Color='w'; ax.XColor='k'; ax.YColor='k';
ax.GridColor=[0.45 0.45 0.45]; ax.GridAlpha=0.18;
ax.Box='on'; grid(ax,'on');
end

function salvar(fig,dirFig,nome)
exportgraphics(fig,fullfile(dirFig,nome+".pdf"), ...
    'ContentType','vector','BackgroundColor','white');
exportgraphics(fig,fullfile(dirFig,nome+".png"), ...
    'Resolution',300,'BackgroundColor','white');
close(fig);
end

function gerarFiguraWcet(s,temporal,dirFig)
ordem=["ATUACAO";"SUPERVISAO";"CONTROLE";"AQUISICAO"];
rotulos={'Atuação','Supervisão','Controle','Aquisição'};
y=(1:4)';
media=zeros(4,1);p99=zeros(4,1);mx=zeros(4,1);
for k=1:4
    r=s(string(s.tarefa)==ordem(k),:);
    media(k)=r.media_us;p99(k)=r.p99_us;mx(k)=r.max_demanda_us;
end
ca=temporal.c_mbwcet_us([1 3 4 5]);

fig=figuraColuna(3.10);ax=axes(fig);hold(ax,'on');preparar(ax);
ax.XScale='log';
for k=1:4
    semilogx(ax,[media(k) ca(k)],[y(k) y(k)],'-','Color',[0.72 0.72 0.72], ...
        'LineWidth',1.0,'HandleVisibility','off');
end
h1=semilogx(ax,media,y,'o','MarkerFaceColor',[0.12 0.47 0.71], ...
    'Color',[0.12 0.47 0.71],'MarkerSize',5);
h2=semilogx(ax,p99,y,'s','MarkerFaceColor',[0.93 0.49 0.19], ...
    'Color',[0.93 0.49 0.19],'MarkerSize',5);
h3=semilogx(ax,mx,y,'d','MarkerFaceColor',[0.47 0.67 0.19], ...
    'Color',[0.47 0.67 0.19],'MarkerSize',5);
h4=semilogx(ax,ca,y,'>','MarkerFaceColor',[0.64 0.18 0.56], ...
    'Color',[0.64 0.18 0.56],'MarkerSize',6);
yticks(ax,y);yticklabels(ax,rotulos);ax.YDir='reverse';ylim(ax,[0.5 4.5]);
xlim(ax,[10 1e6]);
xlabel(ax,'Tempo (us, escala logarítmica)');
title(ax,'Envelope de execução medido','FontSize',10);
lg=legend(ax,[h1 h2 h3 h4],{'Média','P99','Máximo','C_{MB-WCET}'}, ...
    'Location','southoutside','Orientation','horizontal','NumColumns',2, ...
    'FontSize',8);
lg.Color='w';lg.TextColor='k';lg.EdgeColor=[0.4 0.4 0.4];
salvar(fig,dirFig,"A2_WCET_VARIABILIDADE_COL");
end

function gerarFiguraWcrt(w,dirFig)
rotulos={'Atuação','Watchdog','Supervisão','Controle','Aquisição','Cadeia E2E'};
val=[w.uso_deadline_observado_pct w.uso_deadline_wcrt_pct];
fig=figuraColuna(3.45);ax=axes(fig);preparar(ax);
b=barh(ax,val,'grouped','BarWidth',0.74);
b(1).FaceColor=[0.12 0.47 0.71]; b(2).FaceColor=[0.93 0.49 0.19];
yticks(ax,1:6);yticklabels(ax,rotulos);ax.YDir='reverse';
xlabel(ax,'Uso da deadline (%)');xlim(ax,[0 100]);
title(ax,'Resposta observada e limite analítico','FontSize',10);
lg=legend(ax,{'Máximo observado','WCRT'},'Location','southoutside', ...
    'Orientation','horizontal','FontSize',8);
lg.Color='w';lg.TextColor='k';lg.EdgeColor=[0.4 0.4 0.4];
for k=1:6
    text(ax,val(k,1)+1,k-0.15,sprintf('%.1f',val(k,1)), ...
        'FontSize',7.5,'Color',[0.05 0.25 0.45]);
    text(ax,val(k,2)+1,k+0.15,sprintf('%.1f',val(k,2)), ...
        'FontSize',7.5,'Color',[0.65 0.20 0.05]);
end
salvar(fig,dirFig,"A2_WCRT_DEADLINES_COL");
end
