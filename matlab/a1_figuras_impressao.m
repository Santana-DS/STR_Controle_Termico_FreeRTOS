function a1_figuras_impressao(raizRepositorio)
%A1_FIGURAS_IMPRESSAO Figuras de STR dimensionadas para IEEE em duas colunas.
% Gera PNGs de conferencia e PDFs vetoriais. Figuras "col" ocupam uma
% coluna (~89 mm); figuras "wide" ocupam as duas colunas (~182 mm).

if nargin < 1 || strlength(string(raizRepositorio)) == 0
    diretorioScript = fileparts(mfilename('fullpath'));
    raizRepositorio = fileparts(diretorioScript);
end
raizRepositorio = string(raizRepositorio);
set(groot,'defaultFigureColor','w','defaultAxesColor','w', ...
    'defaultAxesXColor','k','defaultAxesYColor','k', ...
    'defaultAxesZColor','k','defaultTextColor','k');
dirResultados = fullfile(raizRepositorio, 'resultados');
dirFiguras = fullfile(dirResultados, 'figuras', 'impressao');
assert(isfolder(dirResultados), 'Repositorio invalido: %s', raizRepositorio);
if ~isfolder(dirFiguras), mkdir(dirFiguras); end

e3 = lerCsv(fullfile(dirResultados, 'traces', 'e3', ...
    'E3_TRACE.csv'));
e5b = lerCsv(fullfile(dirResultados, 'metricas', 'e5b', ...
    'E5B_FASES.csv'));
e8 = lerCsv(fullfile(dirResultados, 'metricas', 'e8', ...
    'E8_METRICAS.csv'));
e9 = lerCsv(fullfile(dirResultados, 'metricas', 'e9', ...
    'E9_METRICAS.csv'));
e10 = lerCsv(fullfile(dirResultados, 'metricas', 'e10', ...
    'E10_METRICAS.csv'));

gerarE3(e3, dirFiguras);
gerarE5b(e5b, dirFiguras);
gerarE8(e8, dirFiguras);
gerarE9(e9, dirFiguras);
gerarE10(e10, dirFiguras);
gerarArquitetura(dirFiguras);
gerarInversao(e10, dirFiguras);

fprintf('Figuras de impressao geradas em: %s\n', dirFiguras);
end

function t = lerCsv(arquivo)
assert(isfile(arquivo), 'Fonte ausente: %s', arquivo);
o = detectImportOptions(arquivo, 'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');
t = readtable(arquivo, o);
end

function fig = figuraColuna(altura)
fig = figure('Color','w','Visible','off','Units','inches', ...
    'Position',[1 1 3.50 altura]);
end

function fig = figuraDupla(altura)
fig = figure('Color','w','Visible','off','Units','inches', ...
    'Position',[1 1 7.16 altura]);
end

function prepararEixos(ax)
ax.FontName = 'Times New Roman';
ax.FontSize = 9;
ax.LineWidth = 0.8;
ax.Color = 'w';
ax.XColor = 'k';
ax.YColor = 'k';
ax.GridColor = [0.45 0.45 0.45];
ax.Box = 'on';
grid(ax,'on');
ax.GridAlpha = 0.18;
end

function salvar(fig, dirFiguras, nome)
pdf = fullfile(dirFiguras, nome + ".pdf");
png = fullfile(dirFiguras, nome + ".png");
exportgraphics(fig, pdf, 'ContentType','vector', 'BackgroundColor','white');
exportgraphics(fig, png, 'Resolution',300, 'BackgroundColor','white');
close(fig);
end

function gerarE3(trace, dirFiguras)
nomes = string(trace.tarefa);
aq = trace(nomes=="AQUISICAO" & trace.sequencia==0,:);
ct = trace(nomes=="CONTROLE" & trace.sequencia==0,:);
at = trace(nomes=="ATUACAO" & trace.sequencia==0,:);
origem = aq.liberacao_us;
ini = ([aq.inicio_us;ct.inicio_us;at.inicio_us]-origem)/1000;
fim = ([aq.termino_us;ct.termino_us;at.termino_us]-origem)/1000;
cores = [0.12 0.47 0.71; 0.93 0.49 0.19; 0.47 0.67 0.19];

fig = figuraColuna(4.05);
tl = tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');
ax = nexttile(tl); hold(ax,'on'); prepararEixos(ax);
barraTarefas(ax,ini,fim,cores);
xline(ax,600,'--','Color',[0.75 0 0],'LineWidth',1.1);
text(ax,592,0.68,'D=600 ms','HorizontalAlignment','right', ...
    'Color',[0.75 0 0],'FontSize',8,'FontWeight','bold');
xlim(ax,[0 635]); ylim(ax,[0.45 3.55]);
yticks(ax,1:3); yticklabels(ax,{'Aquisição','Controle','Atuação'}); ax.YDir='reverse';
xlabel(ax,'Tempo após a liberação (ms)');
title(ax,'(a) Resposta e deadline local','FontSize',9.5);

ax = nexttile(tl); hold(ax,'on'); prepararEixos(ax);
barraTarefas(ax,ini,fim,cores);
xlim(ax,[fim(1)-0.08 fim(3)+0.08]); ylim(ax,[0.45 3.55]);
yticks(ax,1:3); yticklabels(ax,{'Aquisição','Controle','Atuação'}); ax.YDir='reverse';
xlabel(ax,'Tempo após a liberação (ms)');
title(ax,'(b) Ampliação das precedências','FontSize',9.5);
text(ax,mean([ini(2),fim(2)]),2,'535 us','HorizontalAlignment','center', ...
    'VerticalAlignment','bottom','FontSize',8,'FontWeight','bold');
text(ax,mean([ini(3),fim(3)]),3,'65 us','HorizontalAlignment','center', ...
    'VerticalAlignment','bottom','FontSize',8,'FontWeight','bold');
title(tl,'Caminho crítico medido — E3','FontName','Times New Roman', ...
    'FontSize',10,'FontWeight','bold','Color','k');
salvar(fig,dirFiguras,"A1_E3_CAMINHO_CRITICO_COL");
end

function barraTarefas(ax,ini,fim,cores)
for k=1:3
    patch(ax,[ini(k) fim(k) fim(k) ini(k)], ...
        [k-0.25 k-0.25 k+0.25 k+0.25],cores(k,:), ...
        'EdgeColor',0.65*cores(k,:),'LineWidth',0.8);
end
end

function gerarE5b(t,dirFiguras)
baixa=t(t.prioridade==1,:); alta=t(t.prioridade==5,:);
fig=figuraColuna(2.85); ax=axes(fig); hold(ax,'on'); prepararEixos(ax);
plot(ax,baixa.carga_pct,baixa.resposta_aquisicao_max_us/1000,'-o', ...
    'LineWidth',1.4,'MarkerSize',5,'MarkerFaceColor',[0.12 0.47 0.71]);
plot(ax,alta.carga_pct,alta.resposta_aquisicao_max_us/1000,'-s', ...
    'LineWidth',1.4,'MarkerSize',5,'MarkerFaceColor',[0.85 0.33 0.10]);
yline(ax,600,'--','Color',[0.75 0 0],'LineWidth',1.1);
text(ax,2,606,'D=600 ms','Color',[0.75 0 0], ...
    'FontSize',8,'FontWeight','bold');
xlabel(ax,'Carga nominal (%)'); ylabel(ax,'Resposta máxima (ms)');
title(ax,'Sensibilidade à prioridade — E5b','FontSize',10);
legend(ax,{'Prioridade 1','Prioridade 5'},'Location','northwest','FontSize',8);
xlim(ax,[-2 63]); ylim(ax,[360 650]);
text(ax,60,632,'3 perdas','HorizontalAlignment','right','Color',[0.75 0 0], ...
    'FontWeight','bold','FontSize',8.5);
salvar(fig,dirFiguras,"A1_E5B_PRIORIDADES_COL");
end

function gerarE8(t,dirFiguras)
uso=100*t.latencia_max_us./t.deadline_us;
fig=figuraColuna(2.90); ax=axes(fig); prepararEixos(ax);
b=barh(ax,uso,'FaceColor',[0.47 0.67 0.19]); %#ok<NASGU>
yticks(ax,1:5); yticklabels(ax,{'STOP','Sensor','Temperatura','Heartbeat','BOOT'});
ax.YDir='reverse'; xlabel(ax,'Uso da deadline (%)');
title(ax,'Latência dos caminhos seguros — E8','FontSize',10);
xlim(ax,[0 35]);
for k=1:height(t)
    text(ax,uso(k)+0.5,k,sprintf('%.2f%%',uso(k)), ...
        'VerticalAlignment','middle','FontSize',8.5,'FontWeight','bold');
end
salvar(fig,dirFiguras,"A1_E8_MARGENS_FALHAS_COL");
end

function gerarE9(t,dirFiguras)
ops=string(t.operacao); nomes=["ESP_TIMER_PAIR","TRACE_PIPELINE","SNPRINTF_TRACE"];
v=zeros(3,1); for k=1:3, v(k)=t.media_ns(ops==nomes(k))/1000; end
fig=figuraColuna(2.90); ax=axes(fig); prepararEixos(ax);
barh(ax,v,'FaceColor',[0.49 0.18 0.56]);
yticks(ax,1:3); yticklabels(ax,{'Timestamps','Pipeline binário','Formatação textual'});
ax.YDir='reverse'; xlabel(ax,'Custo médio (us)');
title(ax,'Sobrecarga da instrumentação — E9','FontSize',10);
xlim(ax,[0 68]);
for k=1:3
    text(ax,v(k)+1,k,sprintf('%.3f us',v(k)), ...
        'VerticalAlignment','middle','FontSize',8.5,'FontWeight','bold');
end
salvar(fig,dirFiguras,"A1_E9_INSTRUMENTACAO_COL");
end

function gerarE10(t,dirFiguras)
v=t.espera_mediana_us/1000;
fig=figuraColuna(2.90); ax=axes(fig); prepararEixos(ax);
barh(ax,v,'FaceColor',[0.93 0.69 0.13]);
yticks(ax,1:3); yticklabels(ax,{'Mutex baseline','Mutex + herança','Semáforo binário'});
ax.YDir='reverse'; xlabel(ax,'Espera mediana da tarefa alta (ms)');
title(ax,'Bloqueio por recurso compartilhado — E10','FontSize',10);
xlim(ax,[0 72]);
for k=1:3
    rotulo=strrep(sprintf('%.3f ms',round(v(k)+1e-9,3)),'.',',');
    text(ax,v(k)+1,k,rotulo, ...
        'VerticalAlignment','middle','FontSize',8.5,'FontWeight','bold');
end
salvar(fig,dirFiguras,"A1_E10_BLOQUEIO_MEDIDO_COL");
end

function gerarArquitetura(dirFiguras)
fig=figuraDupla(3.15); ax=axes(fig); hold(ax,'on'); axis(ax,[0 12 0 5]); axis(ax,'off');
set(ax,'FontName','Times New Roman');
rectangle(ax,'Position',[0.25 2.50 11.50 2.00],'FaceColor',[0.95 0.97 1], ...
    'EdgeColor',[0.35 0.45 0.65],'LineWidth',0.9);
rectangle(ax,'Position',[0.25 0.35 11.50 1.65],'FaceColor',[0.98 0.98 0.98], ...
    'EdgeColor',[0.45 0.45 0.45],'LineWidth',0.9);
text(ax,0.45,4.25,'Núcleo 1 — caminho crítico','FontWeight','bold','FontSize',9);
text(ax,0.45,1.75,'Núcleo 0 — comunicação e observabilidade','FontWeight','bold','FontSize',9);

node(ax,[0.45 3.00 1.65 0.95],{'Aquisição','T=5,715 s','D=600 ms; P=4'},[0.80 0.90 0.98]);
node(ax,[2.55 3.00 1.65 0.95],{'Controle','D=100 ms; P=5'},[1.00 0.88 0.76]);
node(ax,[4.65 3.00 1.65 0.95],{'Atuação','D=20 ms; P=8'},[0.82 0.94 0.80]);
node(ax,[6.75 3.00 1.65 0.95],{'Watchdog','T=5 ms','D=20 ms; P=7'},[0.90 0.86 0.98]);
node(ax,[8.85 3.00 2.20 0.95],{'Supervisão','T=500 ms; P=6'},[0.98 0.84 0.84]);
node(ax,[1.15 0.65 2.05 0.85],{'Comunicação','D=100 ms; P=3'},[0.91 0.91 0.91]);
node(ax,[5.00 0.65 2.05 0.85],{'Telemetria','D=5,715 s; P=2'},[0.91 0.91 0.91]);
node(ax,[9.05 0.65 1.65 0.85],{'UART / CSV'},[0.93 0.93 0.93]);

seta(ax,[2.10 3.48],[2.55 3.48],'-');
seta(ax,[4.20 3.48],[4.65 3.48],'-');
seta(ax,[6.75 3.30],[6.30 3.30],'--');
seta(ax,[3.20 1.08],[5.00 1.08],'-');
seta(ax,[7.05 1.08],[9.05 1.08],'-');
seta(ax,[3.35 3.00],[5.80 1.50],':');
seta(ax,[7.55 3.00],[6.90 1.50],':');
seta(ax,[3.20 1.25],[6.75 3.25],'--');

rectangle(ax,'Position',[0.60 2.62 1.35 0.35],'Curvature',[1 1], ...
    'FaceColor',[1 0.96 0.72],'EdgeColor',[0.7 0.55 0.1]);
text(ax,1.275,2.795,'ADC + mutex','HorizontalAlignment','center','FontSize',8);
text(ax,3.60,2.72,'mensagens por valor','HorizontalAlignment','center','FontSize',8,'Color',[0.25 0.25 0.25]);
text(ax,9.60,2.30,'trace não bloqueante','HorizontalAlignment','center','FontSize',8,'Color',[0.25 0.25 0.25]);
title(ax,'Arquitetura concorrente e relações temporais','FontName','Times New Roman', ...
    'FontSize',10,'FontWeight','bold');
salvar(fig,dirFiguras,"A1_ARQUITETURA_TAREFAS_WIDE");
end

function node(ax,pos,linhas,cor)
rectangle(ax,'Position',pos,'Curvature',0.08,'FaceColor',cor, ...
    'EdgeColor',[0.25 0.25 0.25],'LineWidth',0.9);
text(ax,pos(1)+pos(3)/2,pos(2)+pos(4)/2,linhas, ...
    'HorizontalAlignment','center','VerticalAlignment','middle', ...
    'FontSize',8,'FontWeight','bold','Color','k');
end

function seta(ax,p1,p2,estilo)
quiver(ax,p1(1),p1(2),p2(1)-p1(1),p2(2)-p1(2),0, ...
    'Color',[0.2 0.2 0.2],'LineWidth',1.0,'LineStyle',estilo, ...
    'MaxHeadSize',0.18);
end

function gerarInversao(t,dirFiguras)
nomes=string(t.cenario);
mutex=t.espera_mediana_us(nomes=="MUTEX_HERANCA")/1000;
bin=t.espera_mediana_us(nomes=="BINARIO_INVERSAO")/1000;
interf=t.janela_media_mediana_us(nomes=="BINARIO_INVERSAO")/1000;
baixo=mutex;

fig=figuraDupla(2.65); ax=axes(fig); hold(ax,'on'); prepararEixos(ax);
hDireto=barh(ax,1,baixo,'FaceColor',[0.12 0.47 0.71],'BarWidth',0.50);
hPilha=barh(ax,2,[baixo interf],'stacked','BarWidth',0.50);
hPilha(1).FaceColor=[0.12 0.47 0.71];
hPilha(2).FaceColor=[0.85 0.33 0.10];
yticks(ax,[1 2]); yticklabels(ax,{'Mutex com herança','Semáforo binário'}); ax.YDir='reverse';
xlabel(ax,'Decomposição da espera da tarefa de alta prioridade (ms)');
title(ax,'Inversão de prioridade: bloqueio limitado versus interferência','FontSize',10);
xlim(ax,[0 64]);
text(ax,baixo/2,1,'seção crítica da tarefa baixa','HorizontalAlignment','center', ...
    'Color','w','FontSize',8,'FontWeight','bold');
text(ax,baixo/2,2,'tarefa baixa','HorizontalAlignment','center', ...
    'Color','w','FontSize',8,'FontWeight','bold');
text(ax,baixo+interf/2,2,'interferência da tarefa média','HorizontalAlignment','center', ...
    'Color','w','FontSize',8,'FontWeight','bold');
text(ax,mutex+0.8,1,sprintf('R_H=%.3f ms',mutex),'VerticalAlignment','middle','FontSize',8.5);
text(ax,bin+0.8,2,sprintf('R_H=%.3f ms',bin),'VerticalAlignment','middle','FontSize',8.5);
legend(ax,[hDireto hPilha(2)],{'bloqueio direto','interferência da tarefa média'},'Location','southoutside', ...
    'Orientation','horizontal','FontSize',8);
salvar(fig,dirFiguras,"A1_INVERSAO_PRIORIDADE_WIDE");
end
